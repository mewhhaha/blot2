// Direct backend: each `(binding, concrete type)` instance becomes one Wasm
// function, emitted once in a single pass over its Core body. Values live in
// Wasm locals laid out by their concrete type; nothing flows between
// functions except arguments and results.
// Port of compiler/src/direct/emit.zig.
//
// Ownership differs from Zig. The type table, the Wasm module and the
// generator state are three root structs owned by direct.compile; Generator
// is a struct of references to them. Slices Zig allocates in arenas are spans
// of grow-only pools in State, and the function emitter's per-body lists are
// stacks in State that each body truncates to its own mark.
namespace blot_direct_emit;
import std;
import binary;
import support.native;
import check.core;
import check.types;
import check.diagnostic_code;
import check.storage_types;
import check.wire_schema;
import direct.writer;
import direct.relocations;
import direct.types;
import direct.runtime;
import direct.map;
import support.zigmap;
import direct.function;

type Ty = u32;
type Error = blot_direct_types::Error;
type Env = blot_direct_types::Env;
type Module = blot_check_core::Module;
type Code = blot_check_diagnostic_code::Code;
type Span = blot_check_core::Span;
type BindingRef = blot_check_core::BindingRef;
type TId = blot_check_types::Id;
type NominalIdentity = blot_check_types::NominalIdentity;
type Operator = blot_check_types::Operator;
type ValType = blot_direct_writer::ValType;
type U64Map = blot_direct_map::U64Map;
type Runtime = blot_direct_runtime::Runtime;
type Chars = const u8[:];

// Bytes in State.text.
struct Text { start: u32 = 0, len: u32 = 0 }
// `code` is storage_unsupported for a form the direct backend lacks; any
// other code is an error in the program itself.
struct Failure { unit: u32 = 0, span: Span = Span { 0, 0 }, message: Text = Text {}, code: Code = blot_check_diagnostic_code::Code.storage_unsupported }

// A value: one Wasm local per word of its type's layout. The locals are
// `len` words at `start` in State.words.
struct Val { ty: Ty = 0, start: u32 = 0, len: u32 = 0 }
// Values in State.vals, types in State.tys, words in State.words.
struct Vals { start: u32 = 0, len: u32 = 0 }
struct Tys { start: u32 = 0, len: u32 = 0 }
struct Words { start: u32 = 0, len: u32 = 0 }
// Zig's `?Val` behind a pointer: a label's result, allocated by the first
// value that reaches it.
struct Slot { present: bool = false, value: Val = Val {} }

// named: a function or constant binding; lambda: a closure node of the
// `parent` instance; partial: a named function applied to its first
// `parent` arguments; primitive: the same for a primitive alias binding;
// constructor: a constructor (catalog index `id`) as a function value.
// host: a Foreign callback adapter calling import `id`; pool: the
// lazily initialized persistent owner of a global array constant.
// trap: a closure of a type no use determines, which traps if called.
// operation: an effect operation's trampoline (id = operation id, ty = its
// signature); state_get / state_set: a state provider's cell accessors.
enum InstanceKind { named, lambda, partial, primitive, constructor, host, pool, trap, operation, state_get, state_set }
fn kindCode(kind: InstanceKind) -> u32 {
    match kind {
        named => { return 0; }, lambda => { return 1; }, partial => { return 2; }, primitive => { return 3; }, constructor => { return 4; },
        host => { return 5; }, pool => { return 6; }, trap => { return 7; }, operation => { return 8; }, state_get => { return 9; }, state_set => { return 10; },
    }
}
fn kindName(kind: InstanceKind) -> Chars {
    match kind {
        named => { return "named"; }, lambda => { return "lambda"; }, partial => { return "partial"; }, primitive => { return "primitive"; },
        constructor => { return "constructor"; }, host => { return "host"; }, pool => { return "pool"; }, trap => { return "trap"; },
        operation => { return "operation"; }, state_get => { return "state_get"; }, state_set => { return "state_set"; },
    }
}
struct InstanceKey { kind: InstanceKind, unit: u32, id: u32, ty: Ty, parent: u32 = 0, evidence_context: u32 = 0 }
fn sameKey(left: InstanceKey, right: InstanceKey) -> bool {
    return left.kind == right.kind && left.unit == right.unit && left.id == right.id && left.ty == right.ty && left.parent == right.parent && left.evidence_context == right.evidence_context;
}
fn hashKey(key: InstanceKey) -> u64 {
    var h: u64 = ((kindCode(key.kind) as u64) << 32) | (key.unit as u64);
    h = (h ^ (h >> 30)) * 0xbf58476d1ce4e5b9;
    h ^= ((key.id as u64) << 32) | (key.ty as u64);
    h = (h ^ (h >> 27)) * 0x94d049bb133111eb;
    if key.parent != 0 || key.evidence_context != 0 {
        h ^= ((key.parent as u64) << 32) | (key.evidence_context as u64);
        h = (h ^ (h >> 27)) * 0x94d049bb133111eb;
    }
    return h ^ (h >> 31);
}
struct Instance {
    key: InstanceKey,
    env: Env = Env {},
    function: u32 = 0,
    parameters: Tys = Tys {},
    result: Ty = 0,
    // Closure convention: the environment pointer is the first parameter.
    // Captures are its contents, and slot is the function's table index.
    closure: bool = false,
    captures: Tys = Tys {},
    slot: u32 = 0,
    // Being emitted to learn its result type; already emitted.
    inferring: bool = false,
    emitted: bool = false,
    // Every hole (`never`) of the key is a part no use reaches, so the
    // instance's unbound scheme variables are unused too.
    unused_holes: bool = false,
    // The unit of the module that created a compiler-owned instance (unit
    // zero: effect operations and state accessors), or 0.
    site: u32 = 0,
    // Offset into State.pool_words for pool instances (0xffffffff otherwise).
    pool_offset: u32 = 0xffffffff,
    // Replay metadata: whether result was inferred from body, and first-seen
    // instance lookup order during body emission.
    was_inferred: bool = false,
    deps_start: u32 = 0,
    deps_len: u32 = 0,
}
struct IndexNode { key: InstanceKey, value: u32, next: u32 }
struct DispatchNode { unit: u32, identity: NominalIdentity, member: u32, operator: Operator, found: bool, target: BindingRef, next: u32 }
struct Recorded { failure: Failure, count: u32 = 1, sample_starts: u32[48] = [0; 48], sample_units: u32[48] = [0; 48] }

// A Core block or loop that `return_`/`break_` can leave, at a Wasm depth.
enum LabelKind { block_, loop_, function }
struct Label {
    target: u32,
    depth: u32,
    // A slot in State.slots, allocated by the first value that leaves the block.
    result: u32,
    // function: the body's own exit, the target of every unmatched return.
    kind: LabelKind = LabelKind.block_,
    // Loops: the backedge target depth, current iteration and exit values.
    top: u32 = 0,
    iteration: Vals = Vals {},
    outgoing: Vals = Vals {},
    // Owner and stack mark locals an iteration releases to, and whether a
    // `continue` already released to them.
    has_release: bool = false,
    // A local that is 1 while every boxed carry came out of the iteration
    // as it went in (0xffffffff: the loop carries none).
    unchanged: u32 = 0xffffffff,
    release_owner: u32 = 0,
    release_stack: u32 = 0,
    allocations: u32 = 0,
    used: bool = false,
    // The local holding the enclosing scope's saved `rt.escape_min_slot`,
    // and the carried owner slots that must predate the iteration for a release to be safe.
    saved_esc: u32 = 0,
    guards: Words = Words {},
    // Carries held in loop slots (boxed values copied in place): one word
    // per carry, nonzero when held.
    slots: Words = Words {},
}
// A shadowed outer local cell owned by a `with` handler: restored into `outer`
// on early `break`/`continue`/`return` out of the `with` suite.
struct HandleCell { cell: u32, outer: Val, ty: Ty, outer_is_cell: bool = false }
// An installed provider: the local holding the effect context from before
// it, and the block depth it was installed at.
struct Handle { saved: u32, depth: u32, cells_start: u32 = 0, cells_len: u32 = 0 }

struct DepEntry { id: u32 }
struct TrapEntry { kind: u8 = 0, unit: u32 = 0, start: u32 = 0, end: u32 = 0, message_start: u32 = 0, message_len: u32 = 0 }
// Four consecutive scalar locals start at w0. A tagged word indexes this
// entry and encodes its lane in the low two bits.
struct V128Shadow {
    w0: u32,
    vloc: u32,
    is_float: bool,
    is_wide: bool = false,
    depth: u32,
    materialized_at: u64 = 0,
}
root struct State {
    instances: Instance[>..] = [],
    // Hash of a key to its newest index node (id + 1).
    instance_index: U64Map = U64Map {},
    index_nodes: IndexNode[>..] = [],
    queue: u32[>..] = [],
    has_failure: bool = false,
    failure: Failure = Failure {},
    // A failure message being written: where it starts in `text`.
    composing: bool = false,
    compose_start: u32 = 0,
    compose_failure: Failure = Failure {},
    solve_depth: u32 = 0,
    // Closures built for function values no use determines (they trap).
    trap_closures: u32 = 0,
    // `dispatchTarget` results by catalog unit, receiver and member.
    dispatch_cache: U64Map = U64Map {},
    dispatch_nodes: DispatchNode[>..] = [],
    // 0 = unknown, 1 = false, 2 = true, indexed by Ty.
    contents_memory: u8[>..] = [],
    // Effect operations (lowered operation types) and their frame ids.
    operation_ids: U64Map = U64Map {},
    // Type variables some scheme quantifies, per unit (built on demand).
    quantified_base: u32[>..] = [],
    quantified_vals: u8[>..] = [],
    failures: Recorded[>..] = [],
    // The storage runtime, emitted on first use.
    has_rt: bool = false,
    rt_flags_known: bool = false,
    rt_has_fork: bool = false,
    rt_has_persistent: bool = false,
    rt: Runtime = Runtime { layout: blot_direct_runtime::Layout {} },
    // Host callback imports by (parameter, result) ABI kinds.
    host_imports: U64Map = U64Map {},
    exported_storage: bool = false,
    // Pool instance globals: (slot, generation, state) stored in `pool_words`
    // at Instance.pool_offset; `pool_order` lists instances for direct.goose.
    pool_words: u32[>..] = [],
    pool_order: u32[>..] = [],
    holds_memory: u8[>..] = [],

    // Pools that only grow.
    text: u8[>..] = [],
    words: u32[>..] = [],
    vals: Val[>..] = [],
    tys: Ty[>..] = [],
    slots: Slot[>..] = [],

    // The function emitter's state. Bodies nest (an instance emitted to
    // infer its result), so each owns the top of these stacks from its mark.
    code: u8[>..<] = [],
    locals: ValType[>..<] = [],
    v128_shadows: V128Shadow[>..<] = [],
    shadow_epoch: u64 = 1,
    labels: Label[>..<] = [],
    handles: Handle[>..<] = [],
    handle_cells: HandleCell[>..] = [],
    handle_cells_len: i64 = 0,
    // Binding tables (zigmap) of every body.
    map_pool: u32[>..] = [],
    // Generalized local function values: (body serial, binding) to node.
    polymorphic: U64Map = U64Map {},
    // Reference counts of local bindings per unit (built on demand).
    use_count_base: u32[>..] = [],
    use_count_vals: u32[>..] = [],
    // Whether a local binding is captured by a closure, per unit (built on demand).
    captured_base: u32[>..] = [],
    captured_vals: u8[>..] = [],
    // Cached canInlineBody eligibility per (unit, binding):
    // 0 = uncomputed; bit 0 = budget 168, bit 1 = budget 152, bit 2 = budget 32, bit 7 = computed.
    inline_ok_base: u32[>..] = [],
    inline_ok_vals: u8[>..] = [],
    // Per-unit linked list of local Tag.reference node ids per binding (built on demand for usesType).
    local_refs_base: u32[>..] = [],
    local_refs_head: u32[>..] = [],
    local_refs_node: u32[>..] = [],
    local_refs_next: u32[>..] = [],
    // Cached interned field name ID per (unit, projection_index):
    // 0xffffffff = uncached, 0xfffffffe = uncached/error fallback.
    proj_field_base: u32[>..] = [],
    proj_field_vals: u32[>..] = [],
    serial: u32 = 0,
    scratch: u32[>..<] = [],
    scratch_bytes: u8[>..<] = [],
    scratch_types: ValType[>..<] = [],
    // Instance dependency tracking for structural per-body replay.
    track_deps: bool = false,
    replaying: bool = false,
    active_instance: u32 = 0xffffffff,
    dep_list: u32[>..] = [],
    dep_scratch: DepEntry[>..<] = [],
    dep_frame_mark: i64 = 0,
    dep_match: bool = true,
    inlined_callees: U64Map = U64Map {},
    persist_rec_helpers: U64Map = U64Map {},
    deep_copy_helpers: U64Map = U64Map {},
    kernels: blot_check_wire_schema::KernelInfo[>..] = [],
    processes: blot_check_wire_schema::ProcessInfo[>..] = [],
    wire_word_tags: u8[>..] = [],
    sparks_vectorized: i64 = 0,
    sparks_scalar_fallback: i64 = 0,
    // Unconditional #run staging dependency & value digest tracking (§4.1 item 3).
    staged_dep_units_valid: bool = false,
    staged_dep_units: u32[>..] = [],
    staged_value_digest: u64 = 0xcbf29ce484222325,
    // Recorded runtime trap sites for the optional `blot:traps` v1 custom section.
    traps: TrapEntry[>..] = [],
    trap_text: u8[>..] = [],
    // Speculative parallel wave emission flags (never serialized).
    parallel_readonly: bool = false,
    parallel_aborted: bool = false,
}

var parallel_inlined: u64[>..] = [];

fn recordStagedDepUnit(g: Generator&, unit: u32) {
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return; }
    if unit == 0 { return; }
    for existing in g.s.staged_dep_units { if existing == unit { return; } }
    g.s.staged_dep_units.push(unit);
}

fn mixStagedDigest(g: Generator&, v: u64) {
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return; }
    g.s.staged_value_digest = (g.s.staged_value_digest ^ v) * 0x100000001b3;
}

fn recordDep(g: Generator&, id: u32) {
    if !g.s.track_deps || g.s.active_instance == 0xffffffff { return; }
    for at in g.s.dep_frame_mark..g.s.dep_scratch.len {
        if g.s.dep_scratch[at].id == id { return; }
    }
    g.s.dep_scratch.push(DepEntry { id });
}
fn recordInlined(g: Generator&, unit: u32, binding: u32) {
    if g.s.track_deps {
        if g.s.parallel_readonly { parallel_inlined.push(key64(unit, binding)); return; }
        g.s.inlined_callees.put(key64(unit, binding), 1);
    }
}

fn resetUnitCaches(s: State&, unit_id: u32) {
    let idx = (unit_id - 1) as i64;
    if idx < s.use_count_base.len { s.use_count_base[idx] = 0xffffffff; }
    if idx < s.quantified_base.len { s.quantified_base[idx] = 0xffffffff; }
    if idx < s.captured_base.len { s.captured_base[idx] = 0xffffffff; }
    if idx < s.inline_ok_base.len { s.inline_ok_base[idx] = 0xffffffff; }
    if idx < s.local_refs_base.len { s.local_refs_base[idx] = 0xffffffff; }
    if idx < s.proj_field_base.len { s.proj_field_base[idx] = 0xffffffff; }
    s.dispatch_cache.clear();
}

fn resetAllCaches(s: State&) {
    for i in 0..s.use_count_base.len { s.use_count_base[i] = 0xffffffff; }
    for i in 0..s.quantified_base.len { s.quantified_base[i] = 0xffffffff; }
    for i in 0..s.captured_base.len { s.captured_base[i] = 0xffffffff; }
    for i in 0..s.inline_ok_base.len { s.inline_ok_base[i] = 0xffffffff; }
    for i in 0..s.local_refs_base.len { s.local_refs_base[i] = 0xffffffff; }
    for i in 0..s.proj_field_base.len { s.proj_field_base[i] = 0xffffffff; }
    s.dispatch_cache.clear();
}

// `units` is the caller's slice. Emitter code reads modules as
// `g.units[unit - 1]` in place: a module reference returned by a helper is
// bounded by `g` for the lifetime checker and then conflicts with every
// stack truncation (Goose spec 5.2).
struct Generator { types: blot_direct_types::Types&, module: blot_direct_writer::Module&, s: State&, units: const Module[:], build_inputs:i64 = -1 }

fn key64(high: u32, low: u32) -> u64 { let wide: u64 = high; return (wide << 32) | low; }

// --- Pools --------------------------------------------------------------

fn wordsOf(g: const Generator&, value: Val) -> const u32[:] { return g.s.words[value.start..value.start + value.len]; }
fn word(g: const Generator&, value: Val, at: i64) -> u32 { return g.s.words[value.start + at]; }
fn valsOf(g: const Generator&, values: Vals) -> const Val[:] { return g.s.vals[values.start..values.start + values.len]; }
fn val(g: const Generator&, values: Vals, at: i64) -> Val { return g.s.vals[values.start + at]; }
fn tysOf(g: const Generator&, values: Tys) -> const Ty[:] { return g.s.tys[values.start..values.start + values.len]; }
fn textOf(g: const Generator&, value: Text) -> Chars { return g.s.text[value.start..value.start + value.len]; }
// `count` default values, to be filled in.
let emit_zeros_u8: u8[256] = [0; 256];
let emit_zeros_u32: u32[64] = [0; 64];
fn growZerosU8(buf: u8[>..]&, count: i64) {
    var rem = count;
    while rem >= 256 { buf.append(emit_zeros_u8[..]); rem -= 256; }
    if rem > 0 { buf.append(emit_zeros_u8[..rem]); }
}
fn growZerosU32(buf: u32[>..]&, count: i64) {
    var rem = count;
    while rem >= 64 { buf.append(emit_zeros_u32[..]); rem -= 64; }
    if rem > 0 { buf.append(emit_zeros_u32[..rem]); }
}
fn reserveVals(g: Generator&, count: i64) -> Vals {
    let start = g.s.vals.len as u32;
    for at in 0..count { g.s.vals.push(Val {}); }
    return Vals { start, count as u32 };
}
fn saveVals(g: Generator&, values: const Val[:]) -> Vals {
    let start = g.s.vals.len as u32;
    g.s.vals.append(values);
    return Vals { start, values.len as u32 };
}
fn saveTys(g: Generator&, values: const Ty[:]) -> Tys {
    let start = g.s.tys.len as u32;
    g.s.tys.append(values);
    return Tys { start, values.len as u32 };
}
fn saveWords(g: Generator&, values: const u32[:]) -> Words {
    let start = g.s.words.len as u32;
    g.s.words.append(values);
    return Words { start, values.len as u32 };
}
fn newSlot(g: Generator&) -> u32 {
    g.s.slots.push(Slot {});
    return (g.s.slots.len - 1) as u32;
}

// --- Failures -----------------------------------------------------------

fn putInt(out: u8[>..]&, value: u64) {
    var digits: u8[20] = [0; 20];
    var count = 0;
    var rest = value;
    loop {
        digits[count] = ('0' + (rest % 10)) as! u8;
        count += 1;
        rest = rest / 10;
        if rest == 0 { break; }
    }
    while count != 0 { count -= 1; out.push(digits[count]); }
}
fn putIntStack(out: u8[>..<]&, value: u64) {
    var digits: u8[20] = [0; 20];
    var count = 0;
    var rest = value;
    loop {
        digits[count] = ('0' + (rest % 10)) as! u8;
        count += 1;
        rest = rest / 10;
        if rest == 0 { break; }
    }
    while count != 0 { count -= 1; out.push(digits[count]); }
}
fn spanOf(m: const Module&, id: u32) -> Span {
    if id < m.spans.len { return m.span(id); }
    return Span { 0, 0 };
}
// Starts a failure message at node `id` of `m`. Like Zig's `fail`, the first
// failure wins: when one is already recorded, the message is discarded.
fn failOpen(g: Generator&, m: const Module&, id: u32) {
    g.s.composing = !g.s.has_failure;
    if !g.s.composing { return; }
    g.s.compose_start = g.s.text.len as u32;
    g.s.compose_failure = Failure { unit: m.unit, span: spanOf(m, id) };
    g.s.text.append("Direct backend: ");
}
// An error in the program, reported with its own diagnostic code.
fn failOpenCode(g: Generator&, m: const Module&, id: u32, code: Code) {
    g.s.composing = !g.s.has_failure;
    if !g.s.composing { return; }
    g.s.compose_start = g.s.text.len as u32;
    g.s.compose_failure = Failure { unit: m.unit, span: spanOf(m, id), code: code };
}
fn put(g: Generator&, text: Chars) { if g.s.composing { g.s.text.append(text); } }
fn putNumber(g: Generator&, value: u64) { if g.s.composing { putInt(g.s.text, value); } }
// Appends an earlier message of the text pool.
fn putText(g: Generator&, text: Text) {
    if !g.s.composing { return; }
    for at in 0..(text.len as i64) { let byte = g.s.text[text.start + at]; g.s.text.push(byte); }
}
fn failClose(g: Generator&) -> Error {
    if g.s.composing {
        g.s.composing = false;
        g.s.failure = g.s.compose_failure;
        g.s.failure.message = Text { g.s.compose_start, (g.s.text.len as u32) - g.s.compose_start };
        g.s.has_failure = true;
    }
    return blot_direct_types::Error.unsupported;
}
fn fail(g: Generator&, m: const Module&, id: u32, text: Chars) -> Error {
    failOpen(g, m, id);
    put(g, text);
    return failClose(g);
}
fn failCode(g: Generator&, m: const Module&, id: u32, code: Code, text: Chars) -> Error {
    failOpenCode(g, m, id, code);
    put(g, text);
    return failClose(g);
}
fn failSpanCode(g: Generator&, unit: u32, span: Span, code: Code, text: Chars) -> Error {
    if !g.s.has_failure {
        let start = g.s.text.len as u32;
        g.s.text.append(text);
        g.s.failure = Failure { unit: unit, span: span, message: Text { start, (g.s.text.len as u32) - start }, code: code };
        g.s.has_failure = true;
    }
    return blot_direct_types::Error.unsupported;
}
// The Zig spelling of a Core node tag.
fn nodeTagName(tag: blot_check_core::Tag) -> Chars {
    if tag == blot_check_core::Tag.block_ { return "block"; }
    if tag == blot_check_core::Tag.match_ { return "match"; }
    if tag == blot_check_core::Tag.loop_ { return "loop"; }
    match tag { const for <N, V> in variants<blot_check_core::Tag> { V => { return N; }, } }
}
fn typeFailure(g: Generator&, m: const Module&, id: u32) -> Error {
    failOpen(g, m, id);
    put(g, "unsupported type (");
    put(g, g.types.failure_reason);
    put(g, ") at a ");
    if id != 0 && id < m.nodes.len { put(g, nodeTagName(m.node(id).tag)); } else { put(g, "declaration"); }
    return failClose(g);
}
fn sameText(g: const Generator&, left: Text, right: Text) -> bool {
    if left.len != right.len { return false; }
    for at in 0..(left.len as i64) { if g.s.text[left.start + at] != g.s.text[right.start + at] { return false; } }
    return true;
}
// Moves the current failure into the build's list, counting repeats.
fn recordFailure(g: Generator&, m: const Module&, id: u32) {
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return; }
    var failure = g.s.failure;
    if !g.s.has_failure {
        let start = g.s.text.len as u32;
        g.s.text.append("Direct backend: unsupported form");
        failure = Failure { unit: m.unit, span: spanOf(m, id), message: Text { start, (g.s.text.len as u32) - start } };
    }
    g.s.has_failure = false;
    for at in 0..g.s.failures.len {
        if sameText(g, g.s.failures[at].failure.message, failure.message) {
            let count = g.s.failures[at].count;
            if count < 48 {
                g.s.failures[at].sample_starts[count] = failure.span.start;
                g.s.failures[at].sample_units[count] = failure.unit;
            }
            g.s.failures[at].count = count + 1;
            return;
        }
    }
    var added = Recorded { failure: failure };
    added.sample_starts[0] = failure.span.start;
    added.sample_units[0] = failure.unit;
    g.s.failures.push(added);
}
// One failure summarizing every distinct unsupported form, if any.
fn summary(g: Generator&) -> Failure, bool {
    if g.s.failures.len == 0 { return Failure {}, false; }
    // An error in the program outranks forms the backend lacks.
    for at in 0..g.s.failures.len {
        let item = g.s.failures[at].failure;
        if item.code != blot_check_diagnostic_code::Code.storage_unsupported { return item, true; }
    }
    let start = g.s.text.len as u32;
    g.s.text.append("Direct backend: ");
    putInt(g.s.text, g.s.failures.len as u64);
    g.s.text.append(" unsupported form(s): ");
    let prefix: Chars = "Direct backend: ";
    for index in 0..g.s.failures.len {
        if index == 24 { g.s.text.append("; ..."); break; }
        if index != 0 { g.s.text.append("; "); }
        let message = g.s.failures[index].failure.message;
        var skip: u32 = 0;
        if message.len >= prefix.len && g.s.text[message.start..message.start + prefix.len] == prefix { skip = prefix.len as u32; }
        for at in (skip as i64)..(message.len as i64) { let byte = g.s.text[message.start + at]; g.s.text.push(byte); }
        g.s.text.append(" (");
        putInt(g.s.text, g.s.failures[index].count);
        g.s.text.append("x at");
        for sample in 0..min(g.s.failures[index].count as i64, 48) {
            g.s.text.push(' ');
            putInt(g.s.text, g.s.failures[index].sample_units[sample]);
            g.s.text.push(':');
            putInt(g.s.text, g.s.failures[index].sample_starts[sample]);
        }
        g.s.text.append(")");
    }
    let first = g.s.failures[0].failure;
    return Failure { unit: first.unit, span: first.span, message: Text { start, (g.s.text.len as u32) - start } }, true;
}
// Discards a failure an optional attempt recorded.
fn dropFailure(g: Generator&) { g.s.has_failure = false; }

// --- Units and dispatch -------------------------------------------------

fn unitModule(g: const Generator&, unit_id: u32) -> const Module& {
    assert(unit_id != 0 && unit_id <= g.units.len);
    return g.units[unit_id - 1];
}
fn hasUnit(g: const Generator&, unit_id: u32) -> bool { return unit_id != 0 && unit_id <= g.units.len; }
// Follows external bindings to their defining declaration. Unit zero in a
// reference means the referring unit `m`.
fn resolve(g: const Generator&, m: const Module&, target: BindingRef) -> BindingRef {
    var current = BindingRef { target.unit, target.binding };
    if target.unit == 0 { current.unit = m.unit; }
    for step in 0..64 {
        if !hasUnit(g, current.unit) { return current; }
        let binding = unitModule(g, current.unit).binding(current.binding);
        if binding.kind != blot_reuse_principal_interface::Kind.external { return current; }
        var next_unit = binding.target.unit;
        if next_unit == 0 { next_unit = current.unit; }
        current = BindingRef { next_unit, binding.target.binding };
    }
    return current;
}

// The associated-function family of a concrete receiver type.
fn receiverIdentity(g: const Generator&, ty: Ty) -> NominalIdentity, bool {
    let n = g.types.node(ty);
    match n.tag {
        nominal => { return g.types.nominalIdentity(ty), true; },
        u32_ => { return NominalIdentity { 0, blot_check_types::u32_type }, true; },
        f32_ => { return NominalIdentity { 0, blot_check_types::f32_type }, true; },
        u8_ => { return NominalIdentity { 0, blot_check_types::u8_type }, true; },
        i32_ => { return NominalIdentity { 0, blot_check_types::i32_type }, true; },
        u64_ => { return NominalIdentity { 0, blot_check_types::u64_type }, true; },
        i64_ => { return NominalIdentity { 0, blot_check_types::i64_type }, true; },
        f64_ => { return NominalIdentity { 0, blot_check_types::f64_type }, true; },
        boolean => { return NominalIdentity { 0, blot_check_types::boolean }, true; },
        unit => { return NominalIdentity { 0, blot_check_types::unit }, true; },
        array => { return NominalIdentity { 0, 0xffffffff }, true; },
        // Storage capabilities are compiler-owned nominal identities.
        ref => { return NominalIdentity { 0xffffffff, blot_check_storage_types::ref }, true; },
        view => { return NominalIdentity { 0xffffffff, blot_check_storage_types::view }, true; },
        link => { return NominalIdentity { 0xffffffff, blot_check_storage_types::link }, true; },
        _ => { return NominalIdentity { 0, 0 }, false; },
    }
}
fn operatorCode(operator: Operator) -> u32 {
    match operator {
        none => { return 0; }, add => { return 1; }, sub => { return 2; }, mul => { return 3; }, div => { return 4; }, rem => { return 5; },
        equal => { return 6; }, not_equal => { return 7; }, less => { return 8; }, less_equal => { return 9; }, greater => { return 10; },
        greater_equal => { return 11; }, bit_and => { return 12; }, bit_or => { return 13; }, bit_xor => { return 14; }, shift_left => { return 15; },
        shift_right => { return 16; },
    }
}
// The associated member `member` (a symbol of `m`) for `identity`: the
// referring unit's catalog first, then the nominal's own unit.
fn dispatchTarget(g: Generator&, m: const Module&, identity: NominalIdentity, member: u32, operator: Operator) -> BindingRef, bool {
    var hashed = ::hash_combine(::hash(m.unit), ::hash(identity.unit));
    hashed = ::hash_combine(hashed, ::hash(identity.decl));
    hashed = ::hash_combine(hashed, ::hash(member));
    hashed = ::hash_combine(hashed, ::hash(operatorCode(operator)));
    let head, known = g.s.dispatch_cache.get(hashed);
    var at = head;
    while at != 0 {
        let entry = g.s.dispatch_nodes[at - 1];
        if entry.unit == m.unit && entry.identity.unit == identity.unit && entry.identity.decl == identity.decl && entry.member == member && entry.operator == operator {
            return entry.target, entry.found;
        }
        at = entry.next;
    }
    let target, found = findDispatchTarget(g, m, identity, member, operator);
    g.s.dispatch_nodes.push(DispatchNode { m.unit, identity, member, operator, found, target, head });
    g.s.dispatch_cache.put(hashed, g.s.dispatch_nodes.len as u32);
    return target, found;
}
fn findDispatchTarget(g: const Generator&, m: const Module&, identity: NominalIdentity, member: u32, operator: Operator) -> BindingRef, bool {
    var owner_unit = m.unit;
    if identity.unit != 0 && identity.unit != 0xffffffff && hasUnit(g, identity.unit) { owner_unit = identity.unit; }
    for index in 0..2 {
        if index == 1 && owner_unit == m.unit { continue; }
        var catalog_unit = m.unit;
        if index == 1 { catalog_unit = owner_unit; }
        let catalog .= unitModule(g, catalog_unit);
        for method in catalog.associated {
            // Unit zero names built-in receivers; nominals carry their unit.
            if method.identity.unit != identity.unit || method.identity.decl != identity.decl { continue; }
            if member != 0 { if method.member != member { continue; } } else if method.operator != operator { continue; }
            var target = method.target;
            if target.unit == 0 { target.unit = catalog.unit; }
            if !hasUnit(g, target.unit) { continue; }
            let defining .= unitModule(g, target.unit);
            if defining.unit != m.unit && defining.binding(target.binding).private { continue; }
            return resolve(g, catalog, target), true;
        }
    }
    return BindingRef { 0, 0 }, false;
}

// `(env, parameter words) -> result words`, the call_indirect type of every
// closure of type `parameter -> result`.
fn closureSignature(g: Generator&, parameter: Ty, result: Ty) -> u32, Error {
    let parameter_words, error = g.types.layout(parameter);
    if error != blot_direct_types::Error.none { return 0, error; }
    let result_words, error = g.types.layout(result);
    if error != blot_direct_types::Error.none { return 0, error; }
    if parameter_words.len < 32 {
        var small: ValType[32] = [0; 32];
        small[0] = blot_direct_writer::VT_i32;
        for w, i in parameter_words { small[i + 1] = w; }
        if g.s.parallel_readonly { return recordParallelSig(g, small[..parameter_words.len + 1], result_words), blot_direct_types::Error.none; }
        return g.module.signature(small[..parameter_words.len + 1], result_words), blot_direct_types::Error.none;
    }
    var words: ValType[>..<] = [];
    words.push(blot_direct_writer::VT_i32);
    words.append(parameter_words);
    if g.s.parallel_readonly { return recordParallelSig(g, words[..], result_words), blot_direct_types::Error.none; }
    return g.module.signature(words[..], result_words), blot_direct_types::Error.none;
}
fn find(g: Generator&, key: InstanceKey) -> u32, bool {
    let head, known = g.s.instance_index.get(hashKey(key));
    var at = head;
    while at != 0 {
        let entry = g.s.index_nodes[at - 1];
        if sameKey(entry.key, key) {
            if g.s.parallel_readonly && (entry.value as i64) >= par_base_insts {
                let ep = par_inst_epoch[(entry.value as i64) - par_base_insts];
                if ep != 0xffffffff && ep != par_job_epoch {
                    at = entry.next;
                    continue;
                }
            }
            recordDep(g, entry.value);
            return entry.value, true;
        }
        at = entry.next;
    }
    return 0, false;
}
// Zig's instance_index.put: the key maps to `id` from now on.
fn indexPut(g: Generator&, key: InstanceKey, id: u32) {
    let hashed = hashKey(key);
    let head, known = g.s.instance_index.get(hashed);
    var at = head;
    while at != 0 {
        if sameKey(g.s.index_nodes[at - 1].key, key) { g.s.index_nodes[at - 1].value = id; return; }
        at = g.s.index_nodes[at - 1].next;
    }
    g.s.index_nodes.push(IndexNode { key, id, head });
    g.s.instance_index.put(hashed, g.s.index_nodes.len as u32);
}
fn unitsHaveFork(units: const Module[:]) -> bool {
    for m in units {
        for node in m.nodes {
            if node.tag == blot_check_core::Tag.fork_ { return true; }
        }
    }
    return false;
}
fn unitsHavePersistentState(units: const Module[:]) -> bool {
    for m in units {
        if m.kernels.len != 0 || m.processes.len != 0 { return true; }
    }
    return false;
}
fn runtime_(g: Generator&) -> const Runtime& {
    if !g.s.has_rt {
        if g.s.parallel_readonly { g.s.parallel_aborted = true; return g.s.rt; }
        var hf = g.s.rt_has_fork;
        var hp = g.s.rt_has_persistent;
        if !g.s.rt_flags_known {
            hf = unitsHaveFork(g.units);
            hp = unitsHavePersistentState(g.units);
        }
        let budgets = blot_direct_runtime::Budgets {
            stack: blot_direct_writer::stackBudget(),
            heap: blot_direct_writer::heapBudget(),
            transport: blot_direct_writer::transportBudget(),
            ..
        };
        g.s.rt = blot_direct_runtime::emitWithOptions(g.module, budgets, hf, hp);
        g.s.has_rt = true;
    }
    return g.s.rt;
}
// Whether the flat contents of `ty` refer to scope memory: an owner, view or
// closure, inline or nested. Boxing is ignored, since a stored or slot-held
// value is copied flat.
recursive fn contentsHoldMemory(g: Generator&, ty: Ty) -> bool, Error {
    if (ty as i64) < g.s.contents_memory.len {
        let hit = g.s.contents_memory[ty];
        if hit != 0 { return hit == 2, blot_direct_types::Error.none; }
    } else {
        growZerosU8(g.s.contents_memory, g.types.nodes.len - g.s.contents_memory.len);
    }
    // A recursive type's flat form is a pointer into scope memory.
    let is_recursive, recursive_error = g.types.isRecursive(ty);
    if recursive_error == blot_direct_types::Error.none && is_recursive { return true, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    var result = false;
    match n.tag {
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never => {},
        function, provider, array, ref, view, link, cell => { result = true; },
        state_provider => {
            let held, error = contentsHoldMemory(g, g.types.words[n.a + 2]);
            if error != blot_direct_types::Error.none { return false, error; }
            result = held;
        },
        tuple => {
            for at in 0..(n.b as i64) {
                let held, error = contentsHoldMemory(g, g.types.words[n.a + at]);
                if error != blot_direct_types::Error.none { return false, error; }
                if held { result = true; break; }
            }
        },
        record => {
            for index in 0..(n.b as i64) {
                let held, error = contentsHoldMemory(g, g.types.recordField(ty, index).ty);
                if error != blot_direct_types::Error.none { return false, error; }
                if held { result = true; break; }
            }
        },
        nominal => {
            g.s.contents_memory[ty] = 1; // recursion guard
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return false, error; }
            for at in 0..(cases.len as i64) {
                let held, error = contentsHoldMemory(g, g.types.variant_payloads[cases.payloads + at]);
                if error != blot_direct_types::Error.none { return false, error; }
                if held { result = true; break; }
            }
        },
    }
    if result { g.s.contents_memory[ty] = 2; } else { g.s.contents_memory[ty] = 1; }
    return result, blot_direct_types::Error.none;
}
// Whether a value of `ty` can refer to scope-allocated memory.
recursive fn holdsMemory(g: Generator&, ty: Ty) -> bool, Error {
    if (ty as i64) < g.s.holds_memory.len {
        let hit = g.s.holds_memory[ty];
        if hit != 0 { return hit == 2, blot_direct_types::Error.none; }
    } else {
        growZerosU8(g.s.holds_memory, g.types.nodes.len - g.s.holds_memory.len);
    }
    // A boxed value is a pointer into scope memory.
    let is_boxed, boxed_error = g.types.boxed(ty);
    if boxed_error == blot_direct_types::Error.none && is_boxed {
        g.s.holds_memory[ty] = 2;
        return true, blot_direct_types::Error.none;
    }
    let n = g.types.node(ty);
    var result = false;
    match n.tag {
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never => {},
        function, provider, array, ref, view, link, cell => { result = true; },
        state_provider => {
            let held, error = holdsMemory(g, g.types.words[n.a + 2]);
            if error != blot_direct_types::Error.none { return false, error; }
            result = held;
        },
        tuple => {
            for at in 0..(n.b as i64) {
                let held, error = holdsMemory(g, g.types.words[n.a + at]);
                if error != blot_direct_types::Error.none { return false, error; }
                if held { result = true; break; }
            }
        },
        record => {
            for index in 0..(n.b as i64) {
                let held, error = holdsMemory(g, g.types.recordField(ty, index).ty);
                if error != blot_direct_types::Error.none { return false, error; }
                if held { result = true; break; }
            }
        },
        nominal => {
            g.s.holds_memory[ty] = 1; // recursion guard
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return false, error; }
            for at in 0..(cases.len as i64) {
                let held, error = holdsMemory(g, g.types.variant_payloads[cases.payloads + at]);
                if error != blot_direct_types::Error.none { return false, error; }
                if held { result = true; break; }
            }
        },
    }
    if result { g.s.holds_memory[ty] = 2; } else { g.s.holds_memory[ty] = 1; }
    return result, blot_direct_types::Error.none;
}

fn signatureOf(g: Generator&, parameters: const Ty[:], result: Ty) -> u32, Error {
    var small: ValType[32] = [0; 32];
    var small_len: i64 = 0;
    var overflow = false;
    var words: ValType[>..<] = [];
    for parameter in parameters {
        let layout, error = g.types.layout(parameter);
        if error != blot_direct_types::Error.none { return 0, error; }
        if !overflow && small_len + layout.len <= 32 {
            for w in layout { small[small_len] = w; small_len += 1; }
        } else {
            if !overflow { words.append(small[..small_len]); overflow = true; }
            words.append(layout);
        }
    }
    let result_words, error = g.types.layout(result);
    if error != blot_direct_types::Error.none { return 0, error; }
    if !overflow { return g.module.signature(small[..small_len], result_words), blot_direct_types::Error.none; }
    return g.module.signature(words[..], result_words), blot_direct_types::Error.none;
}

// The provider frame id of effect operation `operation` (from 1).
fn operationId(g: Generator&, operation: Ty) -> u32 {
    let found, present = g.s.operation_ids.get(operation);
    if present { return found; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0; }
    let id = g.s.operation_ids.count + 1;
    g.s.operation_ids.put(operation, id);
    recordParentAux(1, operation, id);
    return id;
}
recursive fn propagateObligations(g: Generator&, m: const Module&, obligations: const blot_check_types::List[:], mark: i64, depth: i64) {
    var total_obs: i64 = 0;
    for span in obligations { total_obs += span.len as i64; }
    if total_obs == 0 { return; }
    let s .= g.s;
    var done: u64[2] = [0, 0];
    var grew = true;
    while grew {
        grew = false;
        for span, si in obligations {
            for at in 0..(span.len as i64) {
                if si < 2 && at < 64 && ((done[si] >> (at as u64)) & 1) != 0 { continue; }
                let goal = m.obligations[span.start + at];
                // Exactly what solveObligations can derive: a field,
                // element, update, type equality, or shared callee use of a
                // reachable receiver.
                if goal.kind == blot_check_types::ObligationKind.type_eq {
                    let has_l = within(g, m, goal.ty, mark);
                    let has_r = within(g, m, goal.other, mark);
                    if !has_l && !has_r { continue; }
                    let before = s.scratch.len;
                    if has_l { mentions(g, m, goal.other, mark, 0); }
                    if has_r { mentions(g, m, goal.ty, mark, 0); }
                    if s.scratch.len != before { grew = true; }
                    if si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); }
                    continue;
                }
                if goal.kind == blot_check_types::ObligationKind.callee_use {
                    if depth >= 16 { continue; }
                    let decl = goal.identity.decl;
                    if decl == 0 || decl >= m.bindings.len { if si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); } continue; }
                    let pn = m.types.node(goal.ty);
                    if pn.tag != blot_check_types::Tag.product { if si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); } continue; }
                    let cb = m.binding(decl);
                    var arg_ids: u32[64] = [0; 64];
                    var pvar_ids: u32[64] = [0; 64];
                    var count_p: i64 = 0;
                    {
                        let args = m.types.list(blot_check_types::List { pn.a, pn.b });
                        let pvars = m.types.list(cb.public_variables);
                        count_p = args.len;
                        if pvars.len < count_p { count_p = pvars.len; }
                        if count_p > 64 { count_p = 64; }
                        for pi in 0..count_p {
                            arg_ids[pi] = args[pi];
                            pvar_ids[pi] = pvars[pi];
                        }
                    }
                    if count_p == 0 { if si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); } continue; }
                    var known: bool[64] = [false; 64];
                    var any_known = false;
                    for pi in 0..count_p {
                        let k = within(g, m, arg_ids[pi], mark);
                        known[pi] = k;
                        if k { any_known = true; }
                    }
                    if !any_known { continue; }
                    let cmark = s.scratch.len;
                    for pi in 0..count_p {
                        if known[pi] { mentions(g, m, pvar_ids[pi], cmark, 0); }
                    }
                    var cobs: blot_check_types::List[2] = [cb.scheme.obligations, blot_check_types::List {}];
                    let cbody .= m.body(decl);
                    if cbody && (cbody.scheme.obligations.start != cb.scheme.obligations.start || cbody.scheme.obligations.len != cb.scheme.obligations.len) {
                        cobs[1] = cbody.scheme.obligations;
                    }
                    propagateObligations(g, m, cobs[..], cmark, depth + 1);
                    var reached: bool[64] = [false; 64];
                    var all_reached = true;
                    for pi in 0..count_p {
                        let r = within(g, m, pvar_ids[pi], cmark);
                        reached[pi] = r;
                        if !r { all_reached = false; }
                    }
                    s.scratch.resize(cmark);
                    let before = s.scratch.len;
                    for pi in 0..count_p {
                        if reached[pi] { mentions(g, m, arg_ids[pi], mark, 0); }
                    }
                    if s.scratch.len != before { grew = true; }
                    if all_reached && si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); }
                    continue;
                }
                if goal.result == 0 || (goal.kind != blot_check_types::ObligationKind.field && goal.kind != blot_check_types::ObligationKind.writable_field && goal.kind != blot_check_types::ObligationKind.collection && goal.kind != blot_check_types::ObligationKind.update) {
                    if si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); }
                    continue;
                }
                if !within(g, m, goal.ty, mark) { continue; }
                let before = s.scratch.len;
                mentions(g, m, goal.result, mark, 0);
                mentions(g, m, goal.other, mark, 0);
                mentions(g, m, goal.signature, mark, 0);
                if s.scratch.len != before { grew = true; }
                if si < 2 && at < 64 { done[si] |= ((1 as u64) << (at as u64)); }
            }
        }
    }
}
// Whether a scheme of `m` quantifies variable `ty`. A variable none
// quantifies is one the checker left ambiguous: no use fixes it.
// Only variables an instance key can reach count: ones the binding's type
// mentions, or obligations on reachable variables determine. A scheme may
// also quantify variables its body alone leaves open.
fn isQuantified(g: Generator&, m: const Module&, ty: TId) -> bool {
    let uid = (m.unit - 1) as i64;
    while g.s.quantified_base.len < g.units.len { g.s.quantified_base.push(0xffffffff); }
    var base = g.s.quantified_base[uid];
    if base == 0xffffffff {
        base = g.s.quantified_vals.len as u32;
        g.s.quantified_base[uid] = base;
        growZerosU8(g.s.quantified_vals, m.types.nodes.len);
        let s .= g.s;
        let mark = s.scratch.len;
        for index in 0..m.bindings.len {
            let binding = m.bindings[index];
            let body .= m.body(index as u32);
            if binding.scheme.variables.len == 0 && (!body || body.scheme.variables.len == 0) { continue; }
            s.scratch.resize(mark);
            mentions(g, m, binding.ty, mark, 0);
            var obligations: blot_check_types::List[2] = [binding.scheme.obligations, blot_check_types::List {}];
            if body && (body.scheme.obligations.start != binding.scheme.obligations.start || body.scheme.obligations.len != binding.scheme.obligations.len) {
                obligations[1] = body.scheme.obligations;
            }
            // Obligations on reachable receivers reach their results.
            propagateObligations(g, m, obligations[..], mark, 0);
            var schemes: blot_check_types::List[2] = [binding.scheme.variables, blot_check_types::List {}];
            if body && (body.scheme.variables.start != binding.scheme.variables.start || body.scheme.variables.len != binding.scheme.variables.len) {
                schemes[1] = body.scheme.variables;
            }
            for span in schemes {
                for variable in m.types.list(span) {
                    if inScratch(g, mark, s.scratch.len, variable) { g.s.quantified_vals[(base as i64) + (variable as i64)] = 1; }
                }
            }
        }
        s.scratch.resize(mark);
    }
    return g.s.quantified_vals[(base as i64) + (ty as i64)] != 0;
}
fn inScratch(g: const Generator&, from: i64, to: i64, value: u32) -> bool {
    for at in from..to { if g.s.scratch[at] == value { return true; } }
    return false;
}
// Adds the variables of `ty` to the set that starts at `from` on the scratch
// stack and ends at its top.
recursive fn mentions(g: Generator&, m: const Module&, ty: TId, from: i64, depth: i64) {
    if ty <= blot_check_types::never || depth > 64 { return; }
    if g.types.isNoVars(m.unit, ty) { return; }
    let n = m.types.node(ty);
    match n.tag {
        variable, bound => { if !inScratch(g, from, g.s.scratch.len, ty) { g.s.scratch.push(ty); } },
        usage, forall, array => { mentions(g, m, n.a, from, depth + 1); },
        function => {
            mentions(g, m, n.a, from, depth + 1);
            mentions(g, m, n.b, from, depth + 1);
        },
        product => { for child in m.types.list(blot_check_types::List { n.a, n.b }) { mentions(g, m, child, from, depth + 1); } },
        record => { for index in 0..(n.b as i64) { mentions(g, m, m.types.recordField(n, index).ty, from, depth + 1); } },
        nominal => { for argument in m.types.nominalArguments(n) { mentions(g, m, argument, from, depth + 1); } },
        _ => {},
    }
}
// Whether every variable of `ty` is in the set at `reach` on the scratch
// stack (the set ends where this call's own set begins).
fn within(g: Generator&, m: const Module&, ty: TId, reach: i64) -> bool {
    if ty <= blot_check_types::never || g.types.isNoVars(m.unit, ty) { return true; }
    let s .= g.s;
    let found = s.scratch.len;
    mentions(g, m, ty, found, 0);
    var all = true;
    for at in found..s.scratch.len { if !inScratch(g, reach, found, s.scratch[at]) { all = false; break; } }
    s.scratch.resize(found);
    return all;
}

// --- Instances ----------------------------------------------------------

// The instance of a named function at concrete function type `ty`.
recursive fn named(g: Generator&, target: BindingRef, ty: Ty, site: const Module&, site_id: u32) -> u32, Error { return namedWith(g, target, ty, false, site, site_id, 0); }
// `named`, where `unused_holes` says every hole of `ty` is unused.
recursive fn namedWith(g: Generator&, target: BindingRef, ty: Ty, unused_holes: bool, site: const Module&, site_id: u32, evidence_context: u32) -> u32, Error {
    let key = InstanceKey { InstanceKind.named, target.unit, target.binding, ty, 0, evidence_context };
    let found, present = find(g, key);
    if present { return found, blot_direct_types::Error.none; }
    let m .= unitModule(g, target.unit);
    let body .= m.body(target.binding);
    if !body { return 0, fail(g, site, site_id, "call target has no body"); }
    let binding = m.binding(target.binding);
    var env = Env {};
    g.types.match_(m, binding.ty, ty, env);
    let solved = solveObligations(g, m, body.scheme.obligations, env);
    if solved != blot_direct_types::Error.none { return 0, solved; }
    let parameters = m.bodyParameters(body);
    let lowered = Tys { g.s.tys.len as u32, parameters.len as u32 };
    for parameter in parameters { g.s.tys.push(0); }
    for parameter, at in parameters {
        let parameter_ty, error = g.types.lower(m, parameter.ty, env);
        if error != blot_direct_types::Error.none { return 0, typeFailure(g, site, site_id); }
        g.s.tys[lowered.start + at] = parameter_ty;
    }
    // A body such as `@panic` leaves its own type open or `never`; a complete
    // instance type still fixes the result.
    let peeled, has_peeled = peeledResult(g, ty, parameters.len);
    var result, error = g.types.lower(m, m.typeOf(body.root), env);
    if error != blot_direct_types::Error.none {
        // Otherwise the body determines its result type: emit it now.
        if !has_peeled { return inferResultWith(g, key, env, lowered, unused_holes, site, site_id); }
        result = peeled;
    }
    if result == blot_direct_types::never && has_peeled { result = peeled; }
    if g.s.parallel_readonly {
        return addParallelNamed(g, key, env, lowered, result, unused_holes, site.unit), blot_direct_types::Error.none;
    }
    let id, error = addInstance(g, key, env, lowered, result, site, site_id);
    if error != blot_direct_types::Error.none { return 0, error; }
    g.s.instances[id].unused_holes = unused_holes;
    return id, blot_direct_types::Error.none;
}
// The result of `ty` after `count` parameters, when it has no holes.
fn peeledResult(g: const Generator&, ty: Ty, count: i64) -> Ty, bool {
    var result = ty;
    for step in 0..count {
        let n = g.types.node(result);
        if n.tag != blot_direct_types::Tag.function { return 0, false; }
        result = n.b;
    }
    if g.types.concrete(result, 0) { return result, true; }
    return 0, false;
}
// An instance whose result type only its body determines: emitted
// immediately, with its signature fixed once the result is known.
fn inferResult(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, site: const Module&, site_id: u32) -> u32, Error {
    return inferResultWith(g, key, env, parameters, false, site, site_id);
}
recursive fn inferResultWith(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, unused_holes: bool, site: const Module&, site_id: u32) -> u32, Error {
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, blot_direct_types::Error.unsupported; }
    let function = g.module.addFunction(g.module.signature([], []));
    let id = g.s.instances.len as u32;
    g.s.instances.push(Instance { key: key, env: env, function: function, parameters: parameters, result: blot_direct_types::never, inferring: true, emitted: true, unused_holes: unused_holes, was_inferred: true });
    nameFunction(g, function, key);
    indexPut(g, key, id);
    recordDep(g, id);
    let emitted = blot_direct_function::emitInstance(g, id);
    if emitted != blot_direct_types::Error.none { return 0, emitted; }
    g.s.instances[id].inferring = false;
    let signature, error = signatureOf(g, tysOf(g, parameters), g.s.instances[id].result);
    if error != blot_direct_types::Error.none { return 0, typeFailure(g, site, site_id); }
    g.module.functions[function - g.module.imports.len].signature = signature;
    return id, blot_direct_types::Error.none;
}
fn addInstance(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, result: Ty, site: const Module&, site_id: u32) -> u32, Error {
    return addInstanceWith(g, key, env, parameters, result, false, Tys {}, site, site_id);
}
fn addInstanceWith(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, result: Ty, closure: bool, captures: Tys, site: const Module&, site_id: u32) -> u32, Error {
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, blot_direct_types::Error.unsupported; }
    var signature: u32 = 0;
    if closure {
        if parameters.len != 1 { return 0, fail(g, site, site_id, "closures take one parameter"); }
        let made, error = closureSignature(g, g.s.tys[parameters.start], result);
        if error != blot_direct_types::Error.none { return 0, typeFailure(g, site, site_id); }
        signature = made;
    } else {
        let made, error = signatureOf(g, tysOf(g, parameters), result);
        if error != blot_direct_types::Error.none { return 0, typeFailure(g, site, site_id); }
        signature = made;
    }
    let function = g.module.addFunction(signature);
    let id = g.s.instances.len as u32;
    var slot: u32 = 0;
    if closure { slot = g.module.tableSlot(function); }
    g.s.instances.push(Instance { key: key, env: env, function: function, parameters: parameters, result: result, closure: closure, captures: captures, slot: slot, site: site.unit });
    nameFunction(g, function, key);
    indexPut(g, key, id);
    recordDep(g, id);
    g.s.queue.push(id);
    return id, blot_direct_types::Error.none;
}

var name_scratch: u8[>..<] = [];

// Names the function after its source binding, for the name section.
fn nameFunction(g: Generator&, function: u32, key: InstanceKey) {
    if !hasUnit(g, key.unit) { return; }
    let m .= unitModule(g, key.unit);
    let mark = name_scratch.len;
    name_scratch.append(kindName(key.kind));
    name_scratch.push('.');
    match key.kind {
        named, partial, pool => {
            let body .= m.body(key.id);
            if body { name_scratch.append(m.name(body.declaration_name)); } else { name_scratch.append("binding"); }
        },
        lambda => { name_scratch.append("lambda"); },
        primitive => { name_scratch.append("primitive"); },
        constructor => { name_scratch.append("constructor"); },
        host => { name_scratch.append("host"); },
        trap => { name_scratch.append("trap"); },
        operation => { name_scratch.append("operation"); },
        state_get => { name_scratch.append("state_get"); },
        state_set => { name_scratch.append("state_set"); },
    }
    name_scratch.push('#');
    putIntStack(name_scratch, function);
    blot_direct_writer::setName(g.module, function, name_scratch[mark..]);
    name_scratch.resize(mark);
}
// The concrete type of `target` when applied to arguments of the types
// `arguments`: its parameter types fix its variables, obligations the
// dependent ones.
recursive fn calleeFromArguments(g: Generator&, target: BindingRef, arguments: Tys, site: const Module&, site_id: u32, evidence_context: u32) -> Ty, Error {
    let m .= unitModule(g, target.unit);
    let binding = m.binding(target.binding);
    var env = Env {};
    var arrow = binding.ty;
    for argument_at in 0..(arguments.len as i64) {
        let argument = g.s.tys[arguments.start + argument_at];
        var n = m.types.node(arrow);
        while n.tag == blot_check_types::Tag.forall || n.tag == blot_check_types::Tag.usage {
            arrow = n.a;
            n = m.types.node(arrow);
        }
        if n.tag != blot_check_types::Tag.function { break; }
        g.types.match_(m, n.a, argument, env);
        arrow = n.b;
    }
    let body .= m.body(target.binding);
    if body {
        let solved = solveObligations(g, m, body.scheme.obligations, env);
        if solved != blot_direct_types::Error.none { return 0, solved; }
    }
    let solved = solveObligations(g, m, binding.scheme.obligations, env);
    if solved != blot_direct_types::Error.none { return 0, solved; }
    let ty, error = g.types.lower(m, binding.ty, env);
    if error == blot_direct_types::Error.none { return ty, blot_direct_types::Error.none; }
    // Only the body determines the result: key the instance by its parameter
    // types, infer the result, and alias the full type.
    if !body { return 0, typeFailure(g, site, site_id); }
    let parameters = m.bodyParameters(body);
    if !body.is_function || arguments.len < parameters.len { return 0, typeFailure(g, site, site_id); }
    let instance_id, error = namedByParameters(g, target, Tys { arguments.start, parameters.len as u32 }, site, site_id, evidence_context);
    if error != blot_direct_types::Error.none { return 0, error; }
    var full = g.s.instances[instance_id].result;
    var at = parameters.len;
    while at != 0 {
        at -= 1;
        let wrapped, error = g.types.function(g.s.tys[arguments.start + at], full);
        if error != blot_direct_types::Error.none { return 0, error; }
        full = wrapped;
    }
    indexPut(g, InstanceKey { InstanceKind.named, target.unit, target.binding, full, 0, evidence_context }, instance_id);
    return full, blot_direct_types::Error.none;
}
recursive fn namedByParameters(g: Generator&, target: BindingRef, arguments: Tys, site: const Module&, site_id: u32, evidence_context: u32) -> u32, Error {
    var marker = blot_direct_types::never;
    var at = arguments.len as i64;
    while at != 0 {
        at -= 1;
        let wrapped, error = g.types.function(g.s.tys[arguments.start + at], marker);
        if error != blot_direct_types::Error.none { return 0, error; }
        marker = wrapped;
    }
    let key = InstanceKey { InstanceKind.named, target.unit, target.binding, marker, 0, evidence_context };
    let found, present = find(g, key);
    if present { return found, blot_direct_types::Error.none; }
    let m .= unitModule(g, target.unit);
    let body .= m.body(target.binding);
    assert(body);
    var env = Env {};
    let parameters = m.bodyParameters(body);
    let lowered = Tys { g.s.tys.len as u32, parameters.len as u32 };
    for parameter, index in parameters {
        let argument = g.s.tys[arguments.start + index];
        g.types.match_(m, parameter.ty, argument, env);
        g.s.tys.push(argument);
    }
    let solved = solveObligations(g, m, body.scheme.obligations, env);
    if solved != blot_direct_types::Error.none { return 0, solved; }
    let result, error = g.types.lower(m, m.typeOf(body.root), env);
    if error != blot_direct_types::Error.none { return inferResult(g, key, env, lowered, site, site_id); }
    return addInstance(g, key, env, lowered, result, site, site_id);
}

fn solveObligationsPublic(g: Generator&, m: const Module&, goals_span: blot_check_types::List, env: Env&) -> Error { return solveObligations(g, m, goals_span, env); }
// A lambda instance whose result type its body determines.
recursive fn inferClosure(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, captures: Tys, site: const Module&, site_id: u32) -> u32, Error {
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, blot_direct_types::Error.unsupported; }
    let function = g.module.addFunction(g.module.signature([], []));
    let id = g.s.instances.len as u32;
    let slot = g.module.tableSlot(function);
    g.s.instances.push(Instance { key: key, env: env, function: function, parameters: parameters, result: blot_direct_types::never, closure: true, captures: captures, slot: slot, inferring: true, emitted: true, was_inferred: true });
    nameFunction(g, function, key);
    indexPut(g, key, id);
    recordDep(g, id);
    let emitted = blot_direct_function::emitInstance(g, id);
    if emitted != blot_direct_types::Error.none { return 0, emitted; }
    g.s.instances[id].inferring = false;
    if parameters.len != 1 { return 0, fail(g, site, site_id, "closures take one parameter"); }
    let signature, error = closureSignature(g, g.s.tys[parameters.start], g.s.instances[id].result);
    if error != blot_direct_types::Error.none { return 0, typeFailure(g, site, site_id); }
    g.module.functions[function - g.module.imports.len].signature = signature;
    return id, blot_direct_types::Error.none;
}
// Dependent type variables (field and element results) follow from the
// receivers the instance's parameters already fixed.
recursive fn solveObligations(g: Generator&, m: const Module&, goals_span: blot_check_types::List, env: Env&) -> Error {
    let count = goals_span.len as i64;
    if count == 0 { return blot_direct_types::Error.none; }
    var done: u64 = 0;
    var pass: i64 = 0;
    while pass <= count {
        let before = env.count;
        for at in 0..count {
            if at < 64 && ((done >> (at as u64)) & 1) != 0 { continue; }
            let goal = m.obligations[goals_span.start + at];
            if goal.kind == blot_check_types::ObligationKind.type_eq {
                let left, lerr = g.types.lower(m, goal.ty, env);
                if lerr == blot_direct_types::Error.none {
                    g.types.match_(m, goal.other, left, env);
                    if at < 64 { done |= ((1 as u64) << (at as u64)); }
                } else {
                    let right, rerr = g.types.lower(m, goal.other, env);
                    if rerr == blot_direct_types::Error.none {
                        g.types.match_(m, goal.ty, right, env);
                        if at < 64 { done |= ((1 as u64) << (at as u64)); }
                    }
                }
                continue;
            }
            if goal.kind == blot_check_types::ObligationKind.callee_use {
                if g.s.solve_depth >= 32 { continue; }
                let decl = goal.identity.decl;
                if decl == 0 || decl >= m.bindings.len { continue; }
                let pn = m.types.node(goal.ty);
                if pn.tag != blot_check_types::Tag.product { continue; }
                let cb = m.binding(decl);
                var arg_ids: u32[64] = [0; 64];
                var pvar_ids: u32[64] = [0; 64];
                var count_p: i64 = 0;
                {
                    let args = m.types.list(blot_check_types::List { pn.a, pn.b });
                    let pvars = m.types.list(cb.public_variables);
                    count_p = args.len;
                    if pvars.len < count_p { count_p = pvars.len; }
                    if count_p > 64 { count_p = 64; }
                    for pi in 0..count_p {
                        arg_ids[pi] = args[pi];
                        pvar_ids[pi] = pvars[pi];
                    }
                }
                if count_p == 0 { continue; }
                var cenv = Env {};
                var any_known = false;
                for pi in 0..count_p {
                    let cty, cerr = g.types.lower(m, arg_ids[pi], env);
                    if cerr == blot_direct_types::Error.none {
                        g.types.match_(m, pvar_ids[pi], cty, cenv);
                        any_known = true;
                    }
                }
                if !any_known { continue; }
                g.s.solve_depth += 1;
                let cerr1 = solveObligations(g, m, cb.scheme.obligations, cenv);
                if cerr1 != blot_direct_types::Error.none { g.s.solve_depth -= 1; return cerr1; }
                let cbody .= m.body(decl);
                if cbody && (cbody.scheme.obligations.start != cb.scheme.obligations.start || cbody.scheme.obligations.len != cb.scheme.obligations.len) {
                    let cerr2 = solveObligations(g, m, cbody.scheme.obligations, cenv);
                    if cerr2 != blot_direct_types::Error.none { g.s.solve_depth -= 1; return cerr2; }
                }
                g.s.solve_depth -= 1;
                for pi in 0..count_p {
                    let derived, derr = g.types.lower(m, pvar_ids[pi], cenv);
                    if derr == blot_direct_types::Error.none {
                        g.types.match_(m, arg_ids[pi], derived, env);
                    }
                }
                continue;
            }
            if goal.result == 0 { continue; }
            if goal.kind == blot_check_types::ObligationKind.update {
                let receiver, error = g.types.lower(m, goal.ty, env);
                if error != blot_direct_types::Error.none { continue; }
                let n = g.types.node(receiver);
                let name, has_name = g.types.fieldNameOf(m, goal.name, true);
                if !has_name { continue; }
                if n.tag == blot_direct_types::Tag.nominal {
                    var record = receiver;
                    let cases, verr = g.types.variants(receiver);
                    if verr == blot_direct_types::Error.none && cases.len == 1 { record = g.types.variant_payloads[cases.payloads]; }
                    let position = g.types.findField(record, name);
                    if position >= 0 {
                        let old_ty = g.types.recordField(record, position).ty;
                        let assigned, aerr = g.types.lower(m, goal.other, env);
                        if n.b == 0 {
                            g.types.match_(m, goal.other, old_ty, env);
                            g.types.match_(m, goal.result, receiver, env);
                        } else if aerr == blot_direct_types::Error.none {
                            if assigned == old_ty {
                                g.types.match_(m, goal.result, receiver, env);
                            } else {
                                let owner_unit = g.types.words[n.a];
                                if g.hasUnit(owner_unit) {
                                    let owner .= g.units[owner_unit - 1];
                                    let identity = blot_check_types::NominalIdentity { owner_unit, g.types.words[n.a + 1] };
                                    let ordinal, oerr = g.types.nominalOrdinal(owner, identity);
                                    if oerr == blot_direct_types::Error.none {
                                        let ctors = owner.nominalConstructors(ordinal);
                                        if ctors.len == 1 {
                                            let ctor = owner.constructor(ctors[0]);
                                            let payload = owner.types.node(ctor.payload);
                                            if payload.tag == blot_check_types::Tag.record {
                                                var penv = Env {};
                                                for fi in 0..(payload.b as i64) {
                                                    let pf = owner.types.recordField(payload, fi);
                                                    let fn_id, fn_ok = g.types.fieldNameOf(owner, pf.name, true);
                                                    if !fn_ok { continue; }
                                                    if fn_id == name {
                                                        g.types.match_(owner, pf.ty, assigned, penv);
                                                    } else {
                                                        let pos = g.types.findField(record, fn_id);
                                                        if pos >= 0 { g.types.match_(owner, pf.ty, g.types.recordField(record, pos).ty, penv); }
                                                    }
                                                }
                                                let sig = owner.types.node(ctor.scheme.root);
                                                var ret = ctor.scheme.root;
                                                if sig.tag == blot_check_types::Tag.function { ret = sig.b; }
                                                let updated, uerr = g.types.lower(owner, ret, penv);
                                                if uerr == blot_direct_types::Error.none { g.types.match_(m, goal.result, updated, env); }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    continue;
                }
                if n.tag == blot_direct_types::Tag.record {
                    let position = g.types.findField(receiver, name);
                    if position >= 0 {
                        let old_ty = g.types.recordField(receiver, position).ty;
                        let assigned, aerr = g.types.lower(m, goal.other, env);
                        if aerr == blot_direct_types::Error.none {
                            if assigned == old_ty {
                                g.types.match_(m, goal.result, receiver, env);
                            } else {
                                var fields: blot_direct_types::Field[>..<] = [];
                                for fi in 0..(n.b as i64) {
                                    var fld = g.types.recordField(receiver, fi);
                                    if fi == position { fld.ty = assigned; }
                                    fields.push(fld);
                                }
                                let updated, uerr = g.types.record(fields[..]);
                                if uerr == blot_direct_types::Error.none { g.types.match_(m, goal.result, updated, env); }
                            }
                        }
                    }
                    continue;
                }
                continue;
            }
            if goal.kind != blot_check_types::ObligationKind.field && goal.kind != blot_check_types::ObligationKind.writable_field && goal.kind != blot_check_types::ObligationKind.collection {
                if at < 64 { done |= ((1 as u64) << (at as u64)); }
                continue;
            }
            let receiver, error = g.types.lower(m, goal.ty, env);
            if error != blot_direct_types::Error.none { continue; }
            let n = g.types.node(receiver);
            if goal.kind == blot_check_types::ObligationKind.collection {
                match n.tag {
                    array, view => { g.types.match_(m, goal.result, n.a, env); },
                    _ => {},
                }
                if at < 64 { done |= ((1 as u64) << (at as u64)); }
                continue;
            }
            let name, has_name = g.types.fieldNameOf(m, goal.name, true);
            if !has_name { continue; }
            var record = receiver;
            if n.tag == blot_direct_types::Tag.nominal {
                let cases, error = g.types.variants(receiver);
                if error == blot_direct_types::Error.none && cases.len == 1 { record = g.types.variant_payloads[cases.payloads]; }
            }
            let position = g.types.findField(record, name);
            if position >= 0 {
                g.types.match_(m, goal.result, g.types.recordField(record, position).ty, env);
                if at < 64 { done |= ((1 as u64) << (at as u64)); }
                continue;
            }
            // A receiver member: its result at this receiver.
            if g.s.solve_depth >= 32 { continue; }
            let identity, has_identity = receiverIdentity(g, receiver);
            if !has_identity { continue; }
            let target, has_target = dispatchTarget(g, m, identity, goal.name, blot_check_types::Operator.none);
            if !has_target { continue; }
            g.s.solve_depth += 1;
            let callee, error = calleeFromArguments(g, target, saveTys(g, [receiver]), m, 0, 0);
            g.s.solve_depth -= 1;
            if error != blot_direct_types::Error.none {
                if error == blot_direct_types::Error.unsupported { dropFailure(g); continue; }
                return error;
            }
            let arrow = g.types.node(callee);
            if arrow.tag == blot_direct_types::Tag.function {
                g.types.match_(m, goal.result, arrow.b, env);
                if at < 64 { done |= ((1 as u64) << (at as u64)); }
            }
        }
        if env.count == before { return blot_direct_types::Error.none; }
        if count <= 63 && done == (((1 as u64) << (count as u64)) - 1) { return blot_direct_types::Error.none; }
        pass += 1;
    }
    return blot_direct_types::Error.none;
}

let PAR_EV_TRAP: u8 = 1;
let PAR_EV_NAMED: u8 = 2;
let PAR_EV_SIG: u8 = 3;
let PAR_EV_PARTIAL: u8 = 4;
let PAR_EV_POOL: u8 = 5;
let PAR_EV_LAMBDA: u8 = 6;

let PAR_PATCH_CALL: u8 = 1;
let PAR_PATCH_SIG: u8 = 2;
let PAR_PATCH_TRAP: u8 = 3;
let PAR_PATCH_SLOT: u8 = 4;

let PAR_PROV_BIT: u32 = 0x40000000;
let PAR_PROV_MASK: u32 = 0x3fffffff;

struct ParPatch { kind: u8 = 0, code_off: u32 = 0, ev_idx: u32 = 0 }
struct ParProvSig { pstart: u32 = 0, plen: u32 = 0, rstart: u32 = 0, rlen: u32 = 0 }
struct ParAuxEntry { kind: u8 = 0, ty: Ty = 0, val: u32 = 0 }
struct ParPolyEntry { target_inst: u32 = 0, binding: u32 = 0, init_node: u32 = 0 }

var par_base_types: i64 = 0;
var par_base_spellings: i64 = 0;
var par_base_insts: i64 = 0;
var par_job_epoch: u32 = 0;
var par_job_ev_count: u32 = 0;
var par_job_patch_base: i64 = 0;
var par_job_fn_base: i64 = 0;
var par_job_slot_base: i64 = 0;
var par_job_sig_base: i64 = 0;
var par_body_start: i64 = 0;
var par_body_len: i64 = 0;
var par_last_header_len: i64 = 0;
var par_body_buf: u8[>..] = [];
var par_ev_bytes: u8[>..] = [];
var par_patches: ParPatch[>..] = [];
var par_inst_epoch: u32[>..] = [];
var par_inst_ev: u32[>..] = [];
var par_w2p: u32[>..] = [];
var par_p2w: u32[>..] = [];
var par_fn_ev: u32[>..] = [];
var par_slot_ev: u32[>..] = [];
var par_prov_sigs: ParProvSig[>..] = [];
var par_prov_sig_bytes: u8[>..] = [];
var par_prov_sig_ev: u32[>..] = [];
var par_track_aux: bool = false;
var par_parent_aux: ParAuxEntry[>..] = [];
var par_parent_poly: ParPolyEntry[>..] = [];

fn recordParentAux(kind: u8, ty: Ty, val: u32) {
    if par_track_aux { par_parent_aux.push(ParAuxEntry { kind: kind, ty: ty, val: val }); }
}
fn recordParentPoly(target_inst: u32, binding: u32, init_node: u32) {
    if par_track_aux { par_parent_poly.push(ParPolyEntry { target_inst: target_inst, binding: binding, init_node: init_node }); }
}

fn workerToParentInst(w_id: u32) -> u32 {
    if (w_id as i64) < par_base_insts { return w_id; }
    return par_w2p[(w_id as i64) - par_base_insts];
}
fn parentToWorkerInst(p_id: u32) -> u32 {
    if (p_id as i64) < par_base_insts { return p_id; }
    return par_p2w[(p_id as i64) - par_base_insts];
}

fn setParallelBody(header: const u8[:], code: const u8[:], code_base: i64) {
    par_body_start = par_body_buf.len;
    par_body_buf.append(header);
    par_body_buf.append(code);
    par_body_len = par_body_buf.len - par_body_start;
    par_last_header_len = header.len - code_base;
}
fn shiftParallelPatches(mark_at: i64, delta: i64) {
    var i = par_patches.len;
    while i > par_job_patch_base {
        i -= 1;
        if (par_patches[i].code_off as i64) < mark_at { break; }
        par_patches[i].code_off += delta as u32;
    }
}

fn packU32(out: u8[>..<]&, v: u32) {
    out.push(v as! u8);
    out.push((v >> 8) as! u8);
    out.push((v >> 16) as! u8);
    out.push((v >> 24) as! u8);
}

fn packU32Grow(out: u8[>..]&, v: u32) {
    out.push(v as! u8);
    out.push((v >> 8) as! u8);
    out.push((v >> 16) as! u8);
    out.push((v >> 24) as! u8);
}

fn packU64(out: u8[>..<]&, v: u64) {
    packU32(out, v as! u32);
    packU32(out, (v >> 32) as! u32);
}

recursive fn packTyGrow(types: const blot_direct_types::Types&, ty: Ty, out: u8[>..]&) {
    if (ty as i64) < par_base_types {
        out.push(0);
        packU32Grow(out, ty);
        return;
    }
    let n = types.node(ty);
    out.push((blot_direct_types::tagCode(n.tag) + 1) as! u8);
    match n.tag {
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never => {},
        array, ref, view, link, provider, cell => {
            packTyGrow(types, n.a, out);
        },
        function => {
            packTyGrow(types, n.a, out);
            packTyGrow(types, n.b, out);
        },
        tuple => {
            packU32Grow(out, n.b);
            for i in 0..(n.b as i64) { packTyGrow(types, types.words[n.a + i], out); }
        },
        state_provider => {
            packTyGrow(types, types.words[n.a], out);
            packTyGrow(types, types.words[n.a + 1], out);
            packTyGrow(types, types.words[n.a + 2], out);
        },
        nominal => {
            packU32Grow(out, types.words[n.a]);
            packU32Grow(out, types.words[n.a + 1]);
            packU32Grow(out, n.b);
            for i in 0..(n.b as i64) { packTyGrow(types, types.words[n.a + 2 + i], out); }
        },
        record => {
            packU32Grow(out, n.b);
            for i in 0..(n.b as i64) {
                let fld = types.recordField(ty, i);
                if (fld.name as i64) < par_base_spellings {
                    out.push(0);
                    packU32Grow(out, fld.name);
                } else {
                    let sp = types.spelling(fld.name);
                    out.push(1);
                    packU32Grow(out, sp.len as u32);
                    out.append(sp);
                }
                packTyGrow(types, fld.ty, out);
            }
        },
    }
}

recursive fn packTy(types: const blot_direct_types::Types&, ty: Ty, out: u8[>..<]&) {
    if (ty as i64) < par_base_types {
        out.push(0);
        packU32(out, ty);
        return;
    }
    let n = types.node(ty);
    out.push((blot_direct_types::tagCode(n.tag) + 1) as! u8);
    match n.tag {
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never => {},
        array, ref, view, link, provider, cell => {
            packTy(types, n.a, out);
        },
        function => {
            packTy(types, n.a, out);
            packTy(types, n.b, out);
        },
        tuple => {
            packU32(out, n.b);
            for i in 0..(n.b as i64) { packTy(types, types.words[n.a + i], out); }
        },
        state_provider => {
            packTy(types, types.words[n.a], out);
            packTy(types, types.words[n.a + 1], out);
            packTy(types, types.words[n.a + 2], out);
        },
        nominal => {
            packU32(out, types.words[n.a]);
            packU32(out, types.words[n.a + 1]);
            packU32(out, n.b);
            for i in 0..(n.b as i64) { packTy(types, types.words[n.a + 2 + i], out); }
        },
        record => {
            packU32(out, n.b);
            for i in 0..(n.b as i64) {
                let fld = types.recordField(ty, i);
                if (fld.name as i64) < par_base_spellings {
                    out.push(0);
                    packU32(out, fld.name);
                } else {
                    let sp = types.spelling(fld.name);
                    out.push(1);
                    packU32(out, sp.len as u32);
                    out.append(sp);
                }
                packTy(types, fld.ty, out);
            }
        },
    }
}

fn pushUnpackU32(buf: u32[>..]&, len: i64&, value: u32) {
    if len < buf.len { buf[len] = value; } else { buf.push(value); }
    len += 1;
}
fn pushUnpackField(buf: blot_direct_types::Field[>..]&, len: i64&, value: blot_direct_types::Field) {
    if len < buf.len { buf[len] = value; } else { buf.push(value); }
    len += 1;
}

recursive fn unpackTy(
    types: blot_direct_types::Types&,
    pkt: const u8[:],
    pos: i64&,
    ok: bool&,
    u32_buf: u32[>..]&,
    u32_len: i64&,
    fld_buf: blot_direct_types::Field[>..]&,
    fld_len: i64&,
) -> Ty {
    if !ok || pos >= pkt.len { ok = false; return 0; }
    let tag_b = pkt[pos];
    pos += 1;
    if tag_b == 0 {
        if pos + 4 > pkt.len { ok = false; return 0; }
        let id = binary::u32le(pkt, pos);
        pos += 4;
        return id;
    }
    let code = (tag_b - 1) as u32;
    if code == 8 {
        let a = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        let b = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok { return 0; }
        let res, err = types.function(a, b);
        if err != blot_direct_types::Error.none { ok = false; return 0; }
        return res;
    }
    if code == 9 || code == 12 || code == 13 || code == 14 || code == 15 || code == 17 {
        let a = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok { return 0; }
        var tag = blot_direct_types::Tag.array;
        if code == 12 { tag = blot_direct_types::Tag.ref; }
        else if code == 13 { tag = blot_direct_types::Tag.view; }
        else if code == 14 { tag = blot_direct_types::Tag.link; }
        else if code == 15 { tag = blot_direct_types::Tag.provider; }
        else if code == 17 { tag = blot_direct_types::Tag.cell; }
        let res, err = types.intern(tag, [a]);
        if err != blot_direct_types::Error.none { ok = false; return 0; }
        return res;
    }
    if code == 5 {
        if pos + 4 > pkt.len { ok = false; return 0; }
        let count = binary::u32le(pkt, pos) as i64;
        pos += 4;
        let mark = u32_len;
        for i in 0..count { pushUnpackU32(u32_buf, u32_len, 0); }
        for i in 0..count {
            let item = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { u32_len = mark; return 0; }
            u32_buf[mark + i] = item;
        }
        let res, err = types.tuple(u32_buf[mark..mark + count]);
        u32_len = mark;
        if err != blot_direct_types::Error.none { ok = false; return 0; }
        return res;
    }
    if code == 16 {
        let a = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        let b = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        let c = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok { return 0; }
        let res, err = types.intern(blot_direct_types::Tag.state_provider, [a, b, c]);
        if err != blot_direct_types::Error.none { ok = false; return 0; }
        return res;
    }
    if code == 7 {
        if pos + 12 > pkt.len { ok = false; return 0; }
        let u = binary::u32le(pkt, pos);
        let d = binary::u32le(pkt, pos + 4);
        let count = binary::u32le(pkt, pos + 8) as i64;
        pos += 12;
        let mark = u32_len;
        pushUnpackU32(u32_buf, u32_len, u);
        pushUnpackU32(u32_buf, u32_len, d);
        for i in 0..count { pushUnpackU32(u32_buf, u32_len, 0); }
        for i in 0..count {
            let item = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { u32_len = mark; return 0; }
            u32_buf[mark + 2 + i] = item;
        }
        let res, err = types.intern(blot_direct_types::Tag.nominal, u32_buf[mark..mark + 2 + count]);
        u32_len = mark;
        if err != blot_direct_types::Error.none { ok = false; return 0; }
        return res;
    }
    if code == 6 {
        if pos + 4 > pkt.len { ok = false; return 0; }
        let count = binary::u32le(pkt, pos) as i64;
        pos += 4;
        let mark = fld_len;
        for i in 0..count { pushUnpackField(fld_buf, fld_len, blot_direct_types::Field { 0, 0 }); }
        for i in 0..count {
            if pos >= pkt.len { fld_len = mark; ok = false; return 0; }
            let nmode = pkt[pos];
            pos += 1;
            var name_id: u32 = 0;
            if nmode == 0 {
                if pos + 4 > pkt.len { fld_len = mark; ok = false; return 0; }
                name_id = binary::u32le(pkt, pos);
                pos += 4;
            } else {
                if pos + 4 > pkt.len { fld_len = mark; ok = false; return 0; }
                let slen = binary::u32le(pkt, pos) as i64;
                pos += 4;
                if pos + slen > pkt.len { fld_len = mark; ok = false; return 0; }
                name_id = types.fieldName(pkt[pos..pos + slen]);
                pos += slen;
            }
            let fty = unpackTy(types, pkt, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { fld_len = mark; return 0; }
            fld_buf[mark + i] = blot_direct_types::Field { name_id, fty };
        }
        let res, err = types.record(fld_buf[mark..mark + count]);
        fld_len = mark;
        if err != blot_direct_types::Error.none { ok = false; return 0; }
        return res;
    }
    ok = false;
    return 0;
}

fn sameBytes(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for v, i in a { if v != b[i] { return false; } }
    return true;
}

fn recordParallelSig(g: Generator&, params: const ValType[:], results: const ValType[:]) -> u32 {
    let existing, found = g.module.findSignature(params, results);
    if found { return existing; }
    for i in par_job_sig_base..par_prov_sigs.len {
        let s = par_prov_sigs[i];
        let ps = par_prov_sig_bytes[(s.pstart as i64)..(s.pstart as i64) + (s.plen as i64)];
        let rs = par_prov_sig_bytes[(s.rstart as i64)..(s.rstart as i64) + (s.rlen as i64)];
        if sameBytes(ps, params) && sameBytes(rs, results) {
            return PAR_PROV_BIT | ((i - par_job_sig_base) as u32);
        }
    }
    let ev_idx = par_job_ev_count;
    par_job_ev_count += 1;
    par_ev_bytes.push(PAR_EV_SIG);
    packU32Grow(par_ev_bytes, params.len as u32);
    par_ev_bytes.append(params);
    packU32Grow(par_ev_bytes, results.len as u32);
    par_ev_bytes.append(results);
    let rel = (par_prov_sigs.len - par_job_sig_base) as u32;
    let pstart = par_prov_sig_bytes.len as u32;
    par_prov_sig_bytes.append(params);
    let rstart = par_prov_sig_bytes.len as u32;
    par_prov_sig_bytes.append(results);
    par_prov_sigs.push(ParProvSig { pstart: pstart, plen: params.len as u32, rstart: rstart, rlen: results.len as u32 });
    par_prov_sig_ev.push(ev_idx);
    return PAR_PROV_BIT | rel;
}

fn recordParallelTrap(kind: u8, unit: u32, sp_start: u32, sp_end: u32, message: Chars) -> u32 {
    let ev_idx = par_job_ev_count;
    par_job_ev_count += 1;
    par_ev_bytes.push(PAR_EV_TRAP);
    par_ev_bytes.push(kind);
    packU32Grow(par_ev_bytes, unit);
    packU32Grow(par_ev_bytes, sp_start);
    packU32Grow(par_ev_bytes, sp_end);
    packU32Grow(par_ev_bytes, message.len as u32);
    par_ev_bytes.append(message);
    return ev_idx;
}

fn recordParallelTrapPatch(code_off: u32, ev_idx: u32) {
    par_patches.push(ParPatch { kind: PAR_PATCH_TRAP, code_off: code_off, ev_idx: ev_idx });
}

fn tryPatchCall(g: Generator&, fn_id: u32) -> bool {
    if (fn_id & PAR_PROV_BIT) == 0 { return false; }
    let idx = par_job_fn_base + ((fn_id & PAR_PROV_MASK) as i64);
    if idx >= par_fn_ev.len { g.s.parallel_aborted = true; return false; }
    par_patches.push(ParPatch { kind: PAR_PATCH_CALL, code_off: g.s.code.len as u32, ev_idx: par_fn_ev[idx] });
    g.s.code.push(0);
    return true;
}

fn tryPatchSig(g: Generator&, sig_id: u32) -> bool {
    if (sig_id & PAR_PROV_BIT) == 0 { return false; }
    let idx = par_job_sig_base + ((sig_id & PAR_PROV_MASK) as i64);
    if idx >= par_prov_sig_ev.len { g.s.parallel_aborted = true; return false; }
    par_patches.push(ParPatch { kind: PAR_PATCH_SIG, code_off: g.s.code.len as u32, ev_idx: par_prov_sig_ev[idx] });
    g.s.code.push(0);
    return true;
}

fn tryPatchSlot(g: Generator&, slot: u32) -> bool {
    if (slot & PAR_PROV_BIT) == 0 { return false; }
    let idx = par_job_slot_base + ((slot & PAR_PROV_MASK) as i64);
    if idx >= par_slot_ev.len { g.s.parallel_aborted = true; return false; }
    g.s.code.push(blot_direct_writer::OP_i32_const);
    par_patches.push(ParPatch { kind: PAR_PATCH_SLOT, code_off: g.s.code.len as u32, ev_idx: par_slot_ev[idx] });
    g.s.code.push(0);
    return true;
}

fn pushProvisionalInstance(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, result: Ty, closure: bool, captures: Tys, unused_holes: bool, site_unit: u32, ev_idx: u32) -> u32 {
    let fn_id = PAR_PROV_BIT | ((par_fn_ev.len - par_job_fn_base) as u32);
    par_fn_ev.push(ev_idx);
    var slot: u32 = 0;
    if closure {
        slot = PAR_PROV_BIT | ((par_slot_ev.len - par_job_slot_base) as u32);
        par_slot_ev.push(ev_idx);
    }
    let id = g.s.instances.len as u32;
    g.s.instances.push(Instance { key: key, env: env, function: fn_id, parameters: parameters, result: result, closure: closure, captures: captures, slot: slot, unused_holes: unused_holes, site: site_unit });
    par_inst_epoch.push(par_job_epoch);
    par_inst_ev.push(ev_idx);
    par_w2p.push(0xffffffff);
    indexPut(g, key, id);
    recordDep(g, id);
    return id;
}

fn packEnv(types: const blot_direct_types::Types&, head: u32, stop_head: u32, out: u8[>..<]&, full_out: u8&) {
    var nodes: u32[>..<] = [];
    var at = head;
    while at != stop_head && at != 0 {
        nodes.push(at);
        at = types.env_nodes[at].next;
    }
    full_out = if at != stop_head { 1 } else { 0 };
    packU32(out, nodes.len as u32);
    for idx in nodes {
        let en = types.env_nodes[idx];
        packU32(out, en.unit);
        packU32(out, en.ty);
        packTy(types, en.value, out);
    }
}

fn packEnvGrow(types: const blot_direct_types::Types&, head: u32, stop_head: u32, out: u8[>..]&, full_out: u8&) {
    var nodes: u32[>..<] = [];
    var at = head;
    while at != stop_head && at != 0 {
        nodes.push(at);
        at = types.env_nodes[at].next;
    }
    full_out = if at != stop_head { 1 } else { 0 };
    packU32Grow(out, nodes.len as u32);
    for idx in nodes {
        let en = types.env_nodes[idx];
        packU32Grow(out, en.unit);
        packU32Grow(out, en.ty);
        packTyGrow(types, en.value, out);
    }
}

fn addParallelNamed(g: Generator&, key: InstanceKey, env: Env, parameters: Tys, result: Ty, unused_holes: bool, site_unit: u32) -> u32 {
    let ev_idx = par_job_ev_count;
    par_job_ev_count += 1;
    par_ev_bytes.push(PAR_EV_NAMED);
    packU32Grow(par_ev_bytes, key.unit);
    packU32Grow(par_ev_bytes, key.id);
    packTyGrow(g.types, key.ty, par_ev_bytes);
    par_ev_bytes.push(if unused_holes { 1 } else { 0 });
    packU32Grow(par_ev_bytes, site_unit);
    packU32Grow(par_ev_bytes, key.evidence_context);
    var dummy_full: u8 = 0;
    packEnvGrow(g.types, env.head, 0, par_ev_bytes, dummy_full);
    packU32Grow(par_ev_bytes, parameters.len);
    for pi in 0..(parameters.len as i64) {
        packTyGrow(g.types, g.s.tys[parameters.start + pi], par_ev_bytes);
    }
    packTyGrow(g.types, result, par_ev_bytes);
    return pushProvisionalInstance(g, key, env, parameters, result, false, Tys {}, unused_holes, site_unit, ev_idx);
}

fn addParallelPartial(g: Generator&, key: InstanceKey, parameters: Tys, result: Ty, captures: Tys, site_unit: u32) -> u32 {
    let ev_idx = par_job_ev_count;
    par_job_ev_count += 1;
    par_ev_bytes.push(PAR_EV_PARTIAL);
    par_ev_bytes.push(kindCode(key.kind) as! u8);
    packU32Grow(par_ev_bytes, key.unit);
    packU32Grow(par_ev_bytes, key.id);
    packTyGrow(g.types, key.ty, par_ev_bytes);
    packU32Grow(par_ev_bytes, key.parent);
    packU32Grow(par_ev_bytes, key.evidence_context);
    packU32Grow(par_ev_bytes, site_unit);
    return pushProvisionalInstance(g, key, Env {}, parameters, result, true, captures, false, site_unit, ev_idx);
}

fn addParallelPool(g: Generator&, key: InstanceKey, ty: Ty, site_unit: u32) -> u32 {
    let ev_idx = par_job_ev_count;
    par_job_ev_count += 1;
    par_ev_bytes.push(PAR_EV_POOL);
    packU32Grow(par_ev_bytes, key.unit);
    packU32Grow(par_ev_bytes, key.id);
    packTyGrow(g.types, ty, par_ev_bytes);
    packU32Grow(par_ev_bytes, site_unit);
    return pushProvisionalInstance(g, key, Env {}, Tys {}, ty, false, Tys {}, false, site_unit, ev_idx);
}

fn addParallelLambda(g: Generator&, key: InstanceKey, env: Env, orig_head: u32, parameters: Tys, result: Ty, captures: Tys, site_unit: u32) -> u32 {
    let ev_idx = par_job_ev_count;
    par_job_ev_count += 1;
    par_ev_bytes.push(PAR_EV_LAMBDA);
    packU32Grow(par_ev_bytes, key.unit);
    packU32Grow(par_ev_bytes, key.id);
    packTyGrow(g.types, key.ty, par_ev_bytes);
    packU32Grow(par_ev_bytes, workerToParentInst(key.parent));
    packU32Grow(par_ev_bytes, key.evidence_context);
    packU32Grow(par_ev_bytes, site_unit);
    var full_env: u8 = 0;
    var env_nodes: u32[>..<] = [];
    var at = env.head;
    while at != orig_head && at != 0 {
        env_nodes.push(at);
        at = g.types.env_nodes[at].next;
    }
    if at != orig_head { full_env = 1; }
    par_ev_bytes.push(full_env);
    packU32Grow(par_ev_bytes, env_nodes.len as u32);
    for idx in env_nodes {
        let en = g.types.env_nodes[idx];
        packU32Grow(par_ev_bytes, en.unit);
        packU32Grow(par_ev_bytes, en.ty);
        packTyGrow(g.types, en.value, par_ev_bytes);
    }
    packU32Grow(par_ev_bytes, captures.len);
    for ci in 0..(captures.len as i64) {
        packTyGrow(g.types, g.s.tys[captures.start + ci], par_ev_bytes);
    }
    return pushProvisionalInstance(g, key, env, parameters, result, true, captures, false, site_unit, ev_idx);
}

struct SharedSnapshot {
    imports_len: i64 = 0,
    globals_len: i64 = 0,
    exports_len: i64 = 0,
    host_slots: u32 = 0,
    has_memory: bool = false,
    data_len: i64 = 0,
    customs_len: i64 = 0,
    queue_len: i64 = 0,
    traps_len: i64 = 0,
    operation_ids_count: u32 = 0,
    host_imports_count: u32 = 0,
    pool_order_len: i64 = 0,
    persist_rec_count: u32 = 0,
    deep_copy_count: u32 = 0,
    failures_len: i64 = 0,
    staged_dep_len: i64 = 0,
    staged_digest: u64 = 0,
    has_rt: bool = false,
    exported_storage: bool = false,
    trap_closures: u32 = 0,
    reloc_staged: bool = false,
}

fn takeSnapshot(g: const Generator&) -> SharedSnapshot {
    return SharedSnapshot {
        imports_len: g.module.imports.len,
        globals_len: g.module.globals.len,
        exports_len: g.module.exports.len,
        host_slots: g.module.host_slots,
        has_memory: g.module.has_memory,
        data_len: g.module.data.len,
        customs_len: g.module.customs.len,
        queue_len: g.s.queue.len,
        traps_len: g.s.traps.len,
        operation_ids_count: g.s.operation_ids.count,
        host_imports_count: g.s.host_imports.count,
        pool_order_len: g.s.pool_order.len,
        persist_rec_count: g.s.persist_rec_helpers.count,
        deep_copy_count: g.s.deep_copy_helpers.count,
        failures_len: g.s.failures.len,
        staged_dep_len: g.s.staged_dep_units.len,
        staged_digest: g.s.staged_value_digest,
        has_rt: g.s.has_rt,
        exported_storage: g.s.exported_storage,
        trap_closures: g.s.trap_closures,
        reloc_staged: blot_direct_relocations::hasStagedFlag(),
    };
}

fn sameSnapshot(a: SharedSnapshot, b: SharedSnapshot) -> bool {
    return a.imports_len == b.imports_len &&
        a.globals_len == b.globals_len &&
        a.exports_len == b.exports_len &&
        a.host_slots == b.host_slots &&
        a.has_memory == b.has_memory &&
        a.data_len == b.data_len &&
        a.customs_len == b.customs_len &&
        a.queue_len == b.queue_len &&
        a.traps_len == b.traps_len &&
        a.operation_ids_count == b.operation_ids_count &&
        a.host_imports_count == b.host_imports_count &&
        a.pool_order_len == b.pool_order_len &&
        a.persist_rec_count == b.persist_rec_count &&
        a.deep_copy_count == b.deep_copy_count &&
        a.failures_len == b.failures_len &&
        a.staged_dep_len == b.staged_dep_len &&
        a.staged_digest == b.staged_digest &&
        a.has_rt == b.has_rt &&
        a.exported_storage == b.exported_storage &&
        a.trap_closures == b.trap_closures &&
        a.reloc_staged == b.reloc_staged;
}

fn allKindFromCode(code: u8) -> InstanceKind, bool {
    if code == 0 { return InstanceKind.named, true; }
    if code == 1 { return InstanceKind.lambda, true; }
    if code == 2 { return InstanceKind.partial, true; }
    if code == 3 { return InstanceKind.primitive, true; }
    if code == 4 { return InstanceKind.constructor, true; }
    if code == 5 { return InstanceKind.host, true; }
    if code == 6 { return InstanceKind.pool, true; }
    if code == 7 { return InstanceKind.trap, true; }
    if code == 8 { return InstanceKind.operation, true; }
    if code == 9 { return InstanceKind.state_get, true; }
    if code == 10 { return InstanceKind.state_set, true; }
    return InstanceKind.named, false;
}

fn kindFromCode(code: u8) -> InstanceKind, bool {
    if code == 2 { return InstanceKind.partial, true; }
    if code == 3 { return InstanceKind.primitive, true; }
    if code == 4 { return InstanceKind.constructor, true; }
    return InstanceKind.named, false;
}

fn emitWaveSerial(g: Generator&, wave_start: i64, wave_end: i64) -> Error {
    for pos in wave_start..wave_end {
        let id = g.s.queue[pos];
        if g.s.instances[id].emitted { continue; }
        g.s.instances[id].emitted = true;
        let error = blot_direct_function::emitInstance(g, id);
        if error != blot_direct_types::Error.none { return error; }
    }
    return blot_direct_types::Error.none;
}

struct EmitPool {
    handle: u64 = 0,
    width: i64 = 0,
    pids: u32[16] = [0; 16],
    base_types: i64 = 0,
    base_spellings: i64 = 0,
    base_insts: i64 = 0,
    synced_sigs: i64 = 0,
    synced_pool_words: i64 = 0,
    synced_insts: i64 = 0,
    synced_index_nodes: i64 = 0,
    synced_aux: i64 = 0,
    synced_poly: i64 = 0,
    has_rt: bool = false,
    has_memory: bool = false,
    host_slots: u32 = 0,
    exported_storage: bool = false,
}

fn closeEmitPool(pool: EmitPool&) {
    if pool.handle == 0 { return; }
    blot_native::emit_pool_stop(pool.handle);
    for i in 0..pool.width {
        let pid = pool.pids[i];
        if pid != 0 {
            if !blot_native::wait_success(pid) {
                blot_native::persist_kill_child(pid);
                blot_native::wait_success(pid);
            }
            pool.pids[i] = 0;
        }
    }
    blot_native::emit_pool_close(pool.handle);
    pool.handle = 0;
    pool.width = 0;
    par_track_aux = false;
}

fn packSyncDelta(g: const Generator&, pool: EmitPool&, wave_start: i64, wave_end: i64, out: u8[>..<]&) {
    out.clear();
    par_base_types = pool.base_types;
    par_base_spellings = pool.base_spellings;
    // 1. New signatures.
    let sig_count = g.module.signatures.len - pool.synced_sigs;
    packU32(out, sig_count as u32);
    for si in pool.synced_sigs..g.module.signatures.len {
        let s = g.module.signatures[si];
        let ps = blot_direct_writer::types(g.module, s.params);
        let rs = blot_direct_writer::types(g.module, s.results);
        packU32(out, ps.len as u32);
        out.append(ps);
        packU32(out, rs.len as u32);
        out.append(rs);
    }
    pool.synced_sigs = g.module.signatures.len;
    // 2. New pool_words.
    let pw_count = g.s.pool_words.len - pool.synced_pool_words;
    packU32(out, pw_count as u32);
    for pi in pool.synced_pool_words..g.s.pool_words.len {
        packU32(out, g.s.pool_words[pi]);
    }
    pool.synced_pool_words = g.s.pool_words.len;
    // 3. New instances.
    let old_insts = pool.synced_insts;
    let inst_count = g.s.instances.len - old_insts;
    packU32(out, inst_count as u32);
    for p_id in old_insts..g.s.instances.len {
        let inst = g.s.instances[p_id];
        out.push(kindCode(inst.key.kind) as! u8);
        packU32(out, inst.key.unit);
        packU32(out, inst.key.id);
        packTy(g.types, inst.key.ty, out);
        packU32(out, inst.key.parent);
        packU32(out, inst.key.evidence_context);
        packU32(out, inst.function);
        packU32(out, inst.slot);
        packU32(out, inst.site);
        packU32(out, inst.pool_offset);
        var flags: u8 = 0;
        if inst.closure { flags |= 1; }
        if inst.unused_holes { flags |= 2; }
        if inst.emitted { flags |= 4; }
        out.push(flags);
        packTy(g.types, inst.result, out);
        packU32(out, inst.parameters.len);
        for ti in 0..(inst.parameters.len as i64) {
            packTy(g.types, g.s.tys[inst.parameters.start + ti], out);
        }
        packU32(out, inst.captures.len);
        for ci in 0..(inst.captures.len as i64) {
            packTy(g.types, g.s.tys[inst.captures.start + ci], out);
        }
        var dummy_full: u8 = 0;
        packEnv(g.types, inst.env.head, 0, out, dummy_full);
    }
    pool.synced_insts = g.s.instances.len;
    // 4. Extra alias index_nodes (e.g. from inferResult).
    let alias_count_pos = out.len;
    packU32(out, 0);
    var alias_count: u32 = 0;
    for ii in pool.synced_index_nodes..g.s.index_nodes.len {
        let node = g.s.index_nodes[ii];
        if (node.value as i64) < old_insts || !sameKey(node.key, g.s.instances[node.value].key) {
            out.push(kindCode(node.key.kind) as! u8);
            packU32(out, node.key.unit);
            packU32(out, node.key.id);
            packTy(g.types, node.key.ty, out);
            packU32(out, node.key.parent);
            packU32(out, node.key.evidence_context);
            packU32(out, node.value);
            alias_count += 1;
        }
    }
    out[alias_count_pos] = alias_count as! u8;
    out[alias_count_pos + 1] = (alias_count >> 8) as! u8;
    out[alias_count_pos + 2] = (alias_count >> 16) as! u8;
    out[alias_count_pos + 3] = (alias_count >> 24) as! u8;
    pool.synced_index_nodes = g.s.index_nodes.len;
    // 5. Aux maps (operation_ids, deep_copy_helpers, persist_rec_helpers).
    let aux_count = par_parent_aux.len - pool.synced_aux;
    packU32(out, aux_count as u32);
    for ai in pool.synced_aux..par_parent_aux.len {
        let a = par_parent_aux[ai];
        out.push(a.kind);
        packTy(g.types, a.ty, out);
        packU32(out, a.val);
    }
    pool.synced_aux = par_parent_aux.len;
    // 6. Poly captures.
    let poly_count = par_parent_poly.len - pool.synced_poly;
    packU32(out, poly_count as u32);
    for pi in pool.synced_poly..par_parent_poly.len {
        let p = par_parent_poly[pi];
        packU32(out, p.target_inst);
        packU32(out, p.binding);
        packU32(out, p.init_node);
    }
    pool.synced_poly = par_parent_poly.len;
    // 7. Wave job parent instance IDs.
    let wcount = wave_end - wave_start;
    packU32(out, wcount as u32);
    for wi in wave_start..wave_end {
        packU32(out, g.s.queue[wi]);
    }
}

fn applySyncDelta(
    g: Generator&,
    sync: const u8[:],
    wave_ids: u32[>..<]&,
    u32_buf: u32[>..]&,
    fld_buf: blot_direct_types::Field[>..]&,
    eu: u32[>..<]&,
    et: u32[>..<]&,
    ev: Ty[>..<]&,
) -> bool {
    var pos: i64 = 0;
    var ok = true;
    var u32_len: i64 = 0;
    var fld_len: i64 = 0;
    // 1. New signatures.
    if pos + 4 > sync.len { return false; }
    let sig_count = binary::u32le(sync, pos) as i64;
    pos += 4;
    for si in 0..sig_count {
        if pos + 4 > sync.len { return false; }
        let plen = binary::u32le(sync, pos) as i64;
        pos += 4;
        if pos + plen + 4 > sync.len { return false; }
        let pstart = pos;
        pos += plen;
        let rlen = binary::u32le(sync, pos) as i64;
        pos += 4;
        if pos + rlen > sync.len { return false; }
        let rstart = pos;
        pos += rlen;
        g.module.signature(sync[pstart..pstart + plen], sync[rstart..rstart + rlen]);
    }
    // 2. New pool_words.
    if pos + 4 > sync.len { return false; }
    let pw_count = binary::u32le(sync, pos) as i64;
    pos += 4;
    if pos + pw_count * 4 > sync.len { return false; }
    for pi in 0..pw_count {
        g.s.pool_words.push(binary::u32le(sync, pos));
        pos += 4;
    }
    // 3. New instances.
    if pos + 4 > sync.len { return false; }
    let inst_count = binary::u32le(sync, pos) as i64;
    pos += 4;
    for ii in 0..inst_count {
        if pos + 9 > sync.len { return false; }
        let kcode = sync[pos];
        let unit = binary::u32le(sync, pos + 1);
        let item_id = binary::u32le(sync, pos + 5);
        pos += 9;
        let kind, kok = allKindFromCode(kcode);
        if !kok { return false; }
        let kty = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok || pos + 25 > sync.len { return false; }
        var parent = binary::u32le(sync, pos);
        if kind == InstanceKind.lambda { parent = parentToWorkerInst(parent); }
        let ev_ctx = binary::u32le(sync, pos + 4);
        let fn_id = binary::u32le(sync, pos + 8);
        let slot = binary::u32le(sync, pos + 12);
        let site = binary::u32le(sync, pos + 16);
        let pool_off = binary::u32le(sync, pos + 20);
        let flags = sync[pos + 24];
        pos += 25;
        let res_ty = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok || pos + 4 > sync.len { return false; }
        let plen = binary::u32le(sync, pos) as i64;
        pos += 4;
        let pstart = g.s.tys.len as u32;
        for ti in 0..plen {
            let pt = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { return false; }
            g.s.tys.push(pt);
        }
        if pos + 4 > sync.len { return false; }
        let clen = binary::u32le(sync, pos) as i64;
        pos += 4;
        let cstart = g.s.tys.len as u32;
        for ci in 0..clen {
            let ct = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { return false; }
            g.s.tys.push(ct);
        }
        if pos + 4 > sync.len { return false; }
        let elen = binary::u32le(sync, pos) as i64;
        pos += 4;
        eu.clear();
        et.clear();
        ev.clear();
        for ei in 0..elen {
            if pos + 8 > sync.len { return false; }
            eu.push(binary::u32le(sync, pos));
            et.push(binary::u32le(sync, pos + 4));
            pos += 8;
            let v = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { return false; }
            ev.push(v);
        }
        var env = Env {};
        var ri = elen;
        while ri > 0 {
            ri -= 1;
            g.types.envPut(env, eu[ri], et[ri], ev[ri]);
        }
        let key = InstanceKey { kind, unit, item_id, kty, parent, ev_ctx };
        let p_id = (par_base_insts + par_p2w.len) as u32;
        let w_id = g.s.instances.len as u32;
        g.s.instances.push(Instance {
            key: key,
            env: env,
            function: fn_id,
            parameters: Tys { pstart, plen as u32 },
            result: res_ty,
            closure: (flags & 1) != 0,
            captures: Tys { cstart, clen as u32 },
            slot: slot,
            emitted: (flags & 4) != 0,
            unused_holes: (flags & 2) != 0,
            site: site,
            pool_offset: pool_off,
        });
        par_inst_epoch.push(0xffffffff);
        par_inst_ev.push(0);
        par_w2p.push(p_id);
        par_p2w.push(w_id);
        indexPut(g, key, w_id);
    }
    // 4. Extra alias index_nodes.
    if pos + 4 > sync.len { return false; }
    let alias_count = binary::u32le(sync, pos) as i64;
    pos += 4;
    for ai in 0..alias_count {
        if pos + 9 > sync.len { return false; }
        let kcode = sync[pos];
        let unit = binary::u32le(sync, pos + 1);
        let item_id = binary::u32le(sync, pos + 5);
        pos += 9;
        let kind, kok = allKindFromCode(kcode);
        if !kok { return false; }
        let kty = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok || pos + 12 > sync.len { return false; }
        var parent = binary::u32le(sync, pos);
        if kind == InstanceKind.lambda { parent = parentToWorkerInst(parent); }
        let ev_ctx = binary::u32le(sync, pos + 4);
        let val = parentToWorkerInst(binary::u32le(sync, pos + 8));
        pos += 12;
        indexPut(g, InstanceKey { kind, unit, item_id, kty, parent, ev_ctx }, val);
    }
    // 5. Aux maps.
    if pos + 4 > sync.len { return false; }
    let aux_count = binary::u32le(sync, pos) as i64;
    pos += 4;
    for ai in 0..aux_count {
        if pos >= sync.len { return false; }
        let akind = sync[pos];
        pos += 1;
        let aty = unpackTy(g.types, sync, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
        if !ok || pos + 4 > sync.len { return false; }
        let aval = binary::u32le(sync, pos);
        pos += 4;
        if akind == 1 { g.s.operation_ids.put(aty, aval); }
        else if akind == 2 { g.s.deep_copy_helpers.put(key64(aty, 1), aval); }
        else if akind == 3 { g.s.persist_rec_helpers.put(key64(aty, 1), aval); }
    }
    // 6. Poly captures.
    if pos + 4 > sync.len { return false; }
    let poly_count = binary::u32le(sync, pos) as i64;
    pos += 4;
    if pos + poly_count * 12 > sync.len { return false; }
    for pi in 0..poly_count {
        let target_inst = parentToWorkerInst(binary::u32le(sync, pos));
        let binding = binary::u32le(sync, pos + 4);
        let init_node = binary::u32le(sync, pos + 8);
        pos += 12;
        g.s.polymorphic.put(key64(0x80000000 | target_inst, binding), init_node);
    }
    // 7. Wave job parent instance IDs.
    if pos + 4 > sync.len { return false; }
    let wcount = binary::u32le(sync, pos) as i64;
    pos += 4;
    if pos + wcount * 4 != sync.len { return false; }
    wave_ids.clear();
    for wi in 0..wcount {
        wave_ids.push(binary::u32le(sync, pos));
        pos += 4;
    }
    return true;
}

fn runEmitPoolWorker(g: Generator&, handle: u64, lane: u32) {
    par_base_types = g.types.nodes.len;
    par_base_spellings = g.types.spellings.len;
    par_base_insts = g.s.instances.len;
    par_job_epoch = 0;
    let recording = blot_direct_relocations::isRecording();
    var sync_buf: u8[>..<] = [];
    var wave_ids: u32[>..<] = [];
    var pkt: u8[>..<] = [];
    var u32_buf: u32[>..] = [];
    var fld_buf: blot_direct_types::Field[>..] = [];
    var eu: u32[>..<] = [];
    var et: u32[>..<] = [];
    var ev: Ty[>..<] = [];
    var last_gen: u32 = 0;
    loop {
        let next_gen = blot_native::emit_pool_worker_wait(handle, last_gen);
        if next_gen <= 0 { return; }
        last_gen = next_gen as u32;
        let slen = blot_native::emit_pool_sync_len(handle) as i64;
        if slen > sync_buf.len { sync_buf.resize(max(slen, sync_buf.len * 2), 0); }
        if slen == 0 || !blot_native::emit_pool_sync_read(handle, sync_buf[0], slen as u64) {
            blot_native::emit_pool_worker_done(handle, false);
            return;
        }
        g.s.parallel_readonly = false;
        g.module.readonly = false;
        if !applySyncDelta(g, sync_buf[..slen], wave_ids, u32_buf, fld_buf, eu, et, ev) {
            blot_native::emit_pool_worker_done(handle, false);
            return;
        }
        g.s.parallel_readonly = true;
        g.module.readonly = true;
        let base_snap = takeSnapshot(g);
        var poisoned = false;
        loop {
            let span = blot_native::emit_pool_claim_chunk(handle);
            let start = (span >> 32) as i64;
            let end = (span & 0xffffffff) as i64;
            if start >= end { break; }
            for idx in start..end {
                let p_id = wave_ids[idx];
                let w_id = parentToWorkerInst(p_id);
                if g.s.instances[w_id].emitted || poisoned {
                    continue;
                }
                par_job_epoch += 1;
                par_job_ev_count = 0;
                par_body_start = par_body_buf.len;
                par_body_len = 0;
                par_last_header_len = 0;
                let before_ev_bytes = par_ev_bytes.len;
                par_job_patch_base = par_patches.len;
                par_job_fn_base = par_fn_ev.len;
                par_job_slot_base = par_slot_ev.len;
                par_job_sig_base = par_prov_sigs.len;
                let before_inl = parallel_inlined.len;
                g.s.parallel_aborted = false;
                g.module.readonly_hit = false;
                g.s.has_failure = false;
                g.s.composing = false;
                let before_vec = g.s.sparks_vectorized;
                let before_fb = g.s.sparks_scalar_fallback;
                let before_deps = g.s.dep_list.len;
                let save_code = g.s.code.len;
                let save_locals = g.s.locals.len;
                let save_labels = g.s.labels.len;
                let save_handles = g.s.handles.len;
                let save_hcells = g.s.handle_cells_len;
                let save_scratch = g.s.scratch.len;
                let save_sbytes = g.s.scratch_bytes.len;
                let save_stypes = g.s.scratch_types.len;
                let save_depscratch = g.s.dep_scratch.len;
                let save_reloc_mark = blot_direct_relocations::mark();
                let before_bodies = blot_direct_relocations::bodyCount();
                g.s.instances[w_id].emitted = true;
                let err = blot_direct_function::emitInstance(g, w_id);
                let unchanged = sameSnapshot(base_snap, takeSnapshot(g));
                let clean = err == blot_direct_types::Error.none && !g.s.parallel_aborted && !g.module.readonly_hit && !g.s.has_failure && unchanged;
                if clean {
                    pkt.clear();
                    let sv = (g.s.sparks_vectorized - before_vec) as! u64;
                    let sf = (g.s.sparks_scalar_fallback - before_fb) as! u64;
                    let body_len = par_body_len as u32;
                    let deps_len = if g.s.track_deps { (g.s.dep_list.len - before_deps) as u32 } else { 0 };
                    let inl_len = if g.s.track_deps { (parallel_inlined.len - before_inl) as u32 } else { 0 };
                    let sites_len = if recording { (blot_direct_relocations::bodyCount() - before_bodies) as u32 } else { 0 };
                    let ev_count = par_job_ev_count;
                    let ev_bytes_len = (par_ev_bytes.len - before_ev_bytes) as u32;
                    let patches_len = (par_patches.len - par_job_patch_base) as u32;
                    pkt.push(1);
                    packU64(pkt, sv);
                    packU64(pkt, sf);
                    packU32(pkt, body_len);
                    packU32(pkt, deps_len);
                    packU32(pkt, inl_len);
                    packU32(pkt, sites_len);
                    packU32(pkt, ev_count);
                    packU32(pkt, ev_bytes_len);
                    packU32(pkt, patches_len);
                    if par_body_len != 0 { pkt.append(par_body_buf[par_body_start..par_body_start + par_body_len]); }
                    if deps_len != 0 {
                        for di in 0..(deps_len as i64) {
                            var dep_id = g.s.dep_list[before_deps + di];
                            if (dep_id as i64) >= par_base_insts {
                                let rel = (dep_id as i64) - par_base_insts;
                                if par_inst_epoch[rel] == 0xffffffff {
                                    dep_id = par_w2p[rel];
                                } else {
                                    dep_id = 0x80000000 | par_inst_ev[rel];
                                }
                            }
                            packU32(pkt, dep_id);
                        }
                    }
                    if inl_len != 0 {
                        for ii in 0..(inl_len as i64) { packU64(pkt, parallel_inlined[before_inl + ii]); }
                    }
                    if sites_len != 0 {
                        for si in 0..(sites_len as i64) {
                            let rec = blot_direct_relocations::bodyAt(before_bodies + si);
                            packU32(pkt, rec.site.unit);
                            packU32(pkt, rec.site.node);
                            packU64(pkt, rec.site.offset as! u64);
                        }
                    }
                    if ev_bytes_len != 0 {
                        pkt.append(par_ev_bytes[before_ev_bytes..par_ev_bytes.len]);
                    }
                    if patches_len != 0 {
                        let hdr = par_last_header_len as u32;
                        for pi in 0..(patches_len as i64) {
                            let p = par_patches[par_job_patch_base + pi];
                            pkt.push(p.kind);
                            packU32(pkt, hdr + p.code_off);
                            packU32(pkt, p.ev_idx);
                        }
                    }
                    blot_native::emit_pool_lane_append(handle, lane, idx as u32, pkt[0], pkt.len as u64);
                }
                g.s.sparks_vectorized = before_vec;
                g.s.sparks_scalar_fallback = before_fb;
                g.s.code.resize(save_code);
                g.s.locals.resize(save_locals);
                g.s.labels.resize(save_labels);
                g.s.handles.resize(save_handles);
                g.s.handle_cells_len = save_hcells;
                g.s.scratch.resize(save_scratch);
                g.s.scratch_bytes.resize(save_sbytes);
                g.s.scratch_types.resize(save_stypes);
                g.s.dep_scratch.resize(save_depscratch);
                blot_direct_relocations::rewind(save_reloc_mark);
                blot_direct_relocations::rewindBodies(before_bodies);
                if !unchanged { poisoned = true; }
            }
        }
        blot_native::emit_pool_worker_done(handle, !poisoned);
        if poisoned { return; }
    }
}

fn openEmitPool(g: Generator&, pool: EmitPool&, width: i64) -> bool {
    let handle = blot_native::emit_pool_open(width as u32);
    if handle == 0 { return false; }
    pool.handle = handle;
    pool.width = width;
    pool.base_types = g.types.nodes.len;
    pool.base_spellings = g.types.spellings.len;
    pool.base_insts = g.s.instances.len;
    pool.synced_sigs = g.module.signatures.len;
    pool.synced_pool_words = g.s.pool_words.len;
    pool.synced_insts = g.s.instances.len;
    pool.synced_index_nodes = g.s.index_nodes.len;
    pool.synced_aux = par_parent_aux.len;
    pool.synced_poly = par_parent_poly.len;
    pool.has_rt = g.s.has_rt;
    pool.has_memory = g.module.has_memory;
    pool.host_slots = g.module.host_slots;
    pool.exported_storage = g.s.exported_storage;
    var spawned: i64 = 0;
    for lane in 0..width {
        let pid = blot_native::fork_process();
        if pid == 0 {
            runEmitPoolWorker(g, handle, lane as u32);
            blot_native::job_exit(0);
        }
        if pid > 0 {
            pool.pids[lane] = pid as u32;
            spawned += 1;
        } else {
            break;
        }
    }
    if spawned != width {
        pool.width = spawned;
        closeEmitPool(pool);
        return false;
    }
    par_track_aux = true;
    return true;
}

fn replayParallelEvents(
    g: Generator&,
    ev_slice: const u8[:],
    ev_count: i64,
    ev_vals: u32[>..<]&,
    ev_insts: u32[>..<]&,
    u32_buf: u32[>..]&,
    fld_buf: blot_direct_types::Field[>..]&,
    eu: u32[>..<]&,
    et: u32[>..<]&,
    ev: Ty[>..<]&,
    ptmp: Ty[>..<]&,
) -> bool, Error {
    ev_vals.clear();
    ev_insts.clear();
    var u32_len: i64 = 0;
    var fld_len: i64 = 0;
    var pos: i64 = 0;
    for ei in 0..ev_count {
        if pos >= ev_slice.len { return false, blot_direct_types::Error.none; }
        let tag = ev_slice[pos];
        pos += 1;
        if tag == PAR_EV_TRAP {
            if pos + 17 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let kind = ev_slice[pos];
            let unit = binary::u32le(ev_slice, pos + 1);
            let sp_start = binary::u32le(ev_slice, pos + 5);
            let sp_end = binary::u32le(ev_slice, pos + 9);
            let mlen = binary::u32le(ev_slice, pos + 13) as i64;
            pos += 17;
            if pos + mlen > ev_slice.len { return false, blot_direct_types::Error.none; }
            let msg_start = g.s.trap_text.len as u32;
            if mlen != 0 { g.s.trap_text.append(ev_slice[pos..pos + mlen]); }
            pos += mlen;
            g.s.traps.push(TrapEntry { kind: kind, unit: unit, start: sp_start, end: sp_end, message_start: msg_start, message_len: mlen as u32 });
            ev_vals.push(g.s.traps.len as u32);
            ev_insts.push(0);
        } else if tag == PAR_EV_NAMED {
            if pos + 8 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let unit = binary::u32le(ev_slice, pos);
            let binding = binary::u32le(ev_slice, pos + 4);
            pos += 8;
            var ok = true;
            let ty = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok || pos + 13 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let unused_holes = ev_slice[pos] != 0;
            let site_unit = binary::u32le(ev_slice, pos + 1);
            let ev_ctx = binary::u32le(ev_slice, pos + 5);
            let env_len = binary::u32le(ev_slice, pos + 9) as i64;
            pos += 13;
            eu.clear();
            et.clear();
            ev.clear();
            for i in 0..env_len {
                if pos + 8 > ev_slice.len { return false, blot_direct_types::Error.none; }
                eu.push(binary::u32le(ev_slice, pos));
                et.push(binary::u32le(ev_slice, pos + 4));
                pos += 8;
                let v = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
                if !ok { return false, blot_direct_types::Error.none; }
                ev.push(v);
            }
            if pos + 4 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let param_len = binary::u32le(ev_slice, pos) as i64;
            pos += 4;
            ptmp.clear();
            for i in 0..param_len {
                let pt = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
                if !ok { return false, blot_direct_types::Error.none; }
                ptmp.push(pt);
            }
            let result_ty = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok { return false, blot_direct_types::Error.none; }
            let key = InstanceKey { InstanceKind.named, unit, binding, ty, 0, ev_ctx };
            var real_id, present = find(g, key);
            if !present {
                var env = Env {};
                var ri = env_len;
                while ri > 0 {
                    ri -= 1;
                    g.types.envPut(env, eu[ri], et[ri], ev[ri]);
                }
                let pstart = g.s.tys.len as u32;
                for pt in ptmp { g.s.tys.push(pt); }
                let made, err = addInstance(g, key, env, Tys { pstart, param_len as u32 }, result_ty, g.units[site_unit - 1], 0);
                if err != blot_direct_types::Error.none { return false, err; }
                g.s.instances[made].unused_holes = unused_holes;
                real_id = made;
            }
            ev_vals.push(g.s.instances[real_id].function);
            ev_insts.push(real_id);
        } else if tag == PAR_EV_SIG {
            if pos + 4 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let plen = binary::u32le(ev_slice, pos) as i64;
            pos += 4;
            if pos + plen + 4 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let pstart = pos;
            pos += plen;
            let rlen = binary::u32le(ev_slice, pos) as i64;
            pos += 4;
            if pos + rlen > ev_slice.len { return false, blot_direct_types::Error.none; }
            let rstart = pos;
            pos += rlen;
            let real_sig = g.module.signature(ev_slice[pstart..pstart + plen], ev_slice[rstart..rstart + rlen]);
            ev_vals.push(real_sig);
            ev_insts.push(0);
        } else if tag == PAR_EV_PARTIAL {
            if pos + 9 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let kcode = ev_slice[pos];
            let unit = binary::u32le(ev_slice, pos + 1);
            let item_id = binary::u32le(ev_slice, pos + 5);
            pos += 9;
            let kind, kok = kindFromCode(kcode);
            if !kok { return false, blot_direct_types::Error.none; }
            var ok = true;
            let full_ty = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok || pos + 12 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let count = binary::u32le(ev_slice, pos);
            let ev_ctx = binary::u32le(ev_slice, pos + 4);
            let site_unit = binary::u32le(ev_slice, pos + 8);
            pos += 12;
            let key = InstanceKey { kind, unit, item_id, full_ty, count, ev_ctx };
            var real_id, present = find(g, key);
            if !present {
                let captures = Tys { g.s.tys.len as u32, count };
                var rest = full_ty;
                for step in 0..(count as i64) {
                    let arrow = g.types.node(rest);
                    g.s.tys.push(arrow.a);
                    rest = arrow.b;
                }
                let arrow = g.types.node(rest);
                let parameters = saveTys(g, [arrow.a]);
                let made, err = addInstanceWith(g, key, Env {}, parameters, arrow.b, true, captures, g.units[site_unit - 1], 0);
                if err != blot_direct_types::Error.none { return false, err; }
                real_id = made;
            }
            ev_vals.push(g.s.instances[real_id].slot);
            ev_insts.push(real_id);
        } else if tag == PAR_EV_POOL {
            if pos + 8 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let unit = binary::u32le(ev_slice, pos);
            let binding = binary::u32le(ev_slice, pos + 4);
            pos += 8;
            var ok = true;
            let ty = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok || pos + 4 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let site_unit = binary::u32le(ev_slice, pos);
            pos += 4;
            let key = InstanceKey { InstanceKind.pool, unit, binding, ty, 0, 0 };
            var real_id, present = find(g, key);
            if !present {
                let created, err = addInstanceWith(g, key, Env {}, Tys {}, ty, false, Tys {}, g.units[site_unit - 1], 0);
                if err != blot_direct_types::Error.none { return false, err; }
                let at = g.s.pool_words.len as u32;
                let first = g.module.addGlobal(blot_direct_writer::VT_i32, true, 0);
                let second = g.module.addGlobal(blot_direct_writer::VT_i32, true, 0);
                let third = g.module.addGlobal(blot_direct_writer::VT_i32, true, 0);
                g.s.pool_words.push(first);
                g.s.pool_words.push(second);
                g.s.pool_words.push(third);
                g.s.instances[created].pool_offset = at;
                g.s.pool_order.push(created);
                real_id = created;
            }
            ev_vals.push(g.s.instances[real_id].function);
            ev_insts.push(real_id);
        } else if tag == PAR_EV_LAMBDA {
            if pos + 8 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let unit = binary::u32le(ev_slice, pos);
            let node_id = binary::u32le(ev_slice, pos + 4);
            pos += 8;
            var ok = true;
            let ty = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
            if !ok || pos + 17 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let parent_id = binary::u32le(ev_slice, pos);
            let ev_ctx = binary::u32le(ev_slice, pos + 4);
            let site_unit = binary::u32le(ev_slice, pos + 8);
            let full_env = ev_slice[pos + 12];
            let env_len = binary::u32le(ev_slice, pos + 13) as i64;
            pos += 17;
            eu.clear();
            et.clear();
            ev.clear();
            for i in 0..env_len {
                if pos + 8 > ev_slice.len { return false, blot_direct_types::Error.none; }
                eu.push(binary::u32le(ev_slice, pos));
                et.push(binary::u32le(ev_slice, pos + 4));
                pos += 8;
                let v = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
                if !ok { return false, blot_direct_types::Error.none; }
                ev.push(v);
            }
            if pos + 4 > ev_slice.len { return false, blot_direct_types::Error.none; }
            let cap_len = binary::u32le(ev_slice, pos) as i64;
            pos += 4;
            ptmp.clear();
            for i in 0..cap_len {
                let ct = unpackTy(g.types, ev_slice, pos, ok, u32_buf, u32_len, fld_buf, fld_len);
                if !ok { return false, blot_direct_types::Error.none; }
                ptmp.push(ct);
            }
            let key = InstanceKey { InstanceKind.lambda, unit, node_id, ty, parent_id, ev_ctx };
            var real_id, present = find(g, key);
            if !present {
                var env = Env {};
                if full_env == 0 { env = g.s.instances[parent_id].env; }
                var ei2 = env_len;
                while ei2 > 0 {
                    ei2 -= 1;
                    g.types.envPut(env, eu[ei2], et[ei2], ev[ei2]);
                }
                let cap_start = g.s.tys.len as u32;
                for ct in ptmp { g.s.tys.push(ct); }
                let arrow = g.types.node(ty);
                let parameters = saveTys(g, [arrow.a]);
                let made, err = addInstanceWith(g, key, env, parameters, arrow.b, true, Tys { cap_start, cap_len as u32 }, g.units[site_unit - 1], 0);
                if err != blot_direct_types::Error.none { return false, err; }
                real_id = made;
            }
            ev_vals.push(g.s.instances[real_id].slot);
            ev_insts.push(real_id);
        } else {
            return false, blot_direct_types::Error.none;
        }
    }
    return pos == ev_slice.len, blot_direct_types::Error.none;
}

fn emitWavePool(
    g: Generator&,
    pool: EmitPool&,
    wave_start: i64,
    wave_end: i64,
    sync_buf: u8[>..<]&,
    all_lanes: u8[>..<]&,
    job_off: i64[>..<]&,
    job_len: i64[>..<]&,
    ev_vals: u32[>..<]&,
    ev_insts: u32[>..<]&,
    u32_buf: u32[>..]&,
    fld_buf: blot_direct_types::Field[>..]&,
    eu: u32[>..<]&,
    et: u32[>..<]&,
    ev: Ty[>..<]&,
    ptmp: Ty[>..<]&,
    patch_offs: i64[>..<]&,
    patch_deltas: i64[>..<]&,
    enc: u8[>..<]&,
) -> Error, i64 {
    let count = wave_end - wave_start;
    packSyncDelta(g, pool, wave_start, wave_end, sync_buf);
    let chunk_size = max(1, min(8, count / (pool.width * 4))) as u32;
    if !blot_native::emit_pool_begin_wave(pool.handle, count as u32, chunk_size, sync_buf[0], sync_buf.len as u64) ||
       !blot_native::emit_pool_wait_wave(pool.handle, pool.pids[0], pool.width as u32) {
        closeEmitPool(pool);
        return emitWaveSerial(g, wave_start, wave_end), 0;
    }
    var total_bytes: i64 = 0;
    for lane in 0..pool.width {
        total_bytes += blot_native::emit_pool_lane_size(pool.handle, lane as u32) as i64;
    }
    all_lanes.clear();
    if total_bytes > 0 {
        all_lanes.resize(total_bytes, 0);
        var dst_pos: i64 = 0;
        for lane in 0..pool.width {
            let lsz = blot_native::emit_pool_lane_size(pool.handle, lane as u32) as i64;
            if lsz > 0 {
                blot_native::emit_pool_lane_read(pool.handle, lane as u32, all_lanes[dst_pos], lsz as u64);
                dst_pos += lsz;
            }
        }
    }
    job_off.clear();
    job_len.clear();
    job_off.resize(count, -1);
    job_len.resize(count, 0);
    var scan: i64 = 0;
    while scan + 8 <= total_bytes {
        let jidx = binary::u32le(all_lanes[..total_bytes], scan) as i64;
        let plen = binary::u32le(all_lanes[..total_bytes], scan + 4) as i64;
        scan += 8;
        if scan + plen > total_bytes { break; }
        if jidx >= 0 && jidx < count {
            job_off[jidx] = scan;
            job_len[jidx] = plen;
        }
        scan += plen;
    }
    let recording = blot_direct_relocations::isRecording();
    var wave_err = blot_direct_types::Error.none;
    var applied_count: i64 = 0;
    for idx in 0..count {
        let id = g.s.queue[wave_start + idx];
        if g.s.instances[id].emitted { continue; }
        let off = job_off[idx];
        let size = job_len[idx];
        var applied = false;
        if off >= 0 && size >= 45 && all_lanes[off] == 1 {
            let pkt = all_lanes[off..off + size];
            let sv = binary::u64le(pkt, 1) as! i64;
            let sf = binary::u64le(pkt, 9) as! i64;
            let body_len = binary::u32le(pkt, 17) as i64;
            let deps_len = binary::u32le(pkt, 21) as i64;
            let inl_len = binary::u32le(pkt, 25) as i64;
            let sites_len = binary::u32le(pkt, 29) as i64;
            let ev_count = binary::u32le(pkt, 33) as i64;
            let ev_bytes_len = binary::u32le(pkt, 37) as i64;
            let patches_len = binary::u32le(pkt, 41) as i64;
            let expected = 45 + body_len + deps_len * 4 + inl_len * 8 + sites_len * 16 + ev_bytes_len + patches_len * 9;
            if expected == size {
                let body_pos: i64 = 45;
                let deps_pos = body_pos + body_len;
                let inl_pos = deps_pos + deps_len * 4;
                let sites_pos = inl_pos + inl_len * 8;
                let ev_pos = sites_pos + sites_len * 16;
                let patches_pos = ev_pos + ev_bytes_len;
                var ev_ok = true;
                if ev_count != 0 {
                    let rok, rerr = replayParallelEvents(g, pkt[ev_pos..ev_pos + ev_bytes_len], ev_count, ev_vals, ev_insts, u32_buf, fld_buf, eu, et, ev, ptmp);
                    if rerr != blot_direct_types::Error.none { wave_err = rerr; break; }
                    ev_ok = rok;
                } else {
                    ev_vals.clear();
                    ev_insts.clear();
                }
                if ev_ok {
                    g.s.sparks_vectorized += sv;
                    g.s.sparks_scalar_fallback += sf;
                    let body_start = g.module.text.len;
                    patch_offs.clear();
                    patch_deltas.clear();
                    if patches_len == 0 {
                        if body_len != 0 { g.module.text.append(pkt[body_pos..body_pos + body_len]); }
                    } else {
                        var cursor: i64 = 0;
                        for pi in 0..patches_len {
                            let pbase = patches_pos + pi * 9;
                            let pkind = pkt[pbase];
                            let poff = binary::u32le(pkt, pbase + 1) as i64;
                            let pev = binary::u32le(pkt, pbase + 5) as i64;
                            if poff > cursor { g.module.text.append(pkt[body_pos + cursor..body_pos + poff]); }
                            let pval = ev_vals[pev];
                            enc.clear();
                            if pkind == PAR_PATCH_CALL || pkind == PAR_PATCH_SIG {
                                blot_direct_writer::uleb(enc, pval as u64);
                            } else {
                                blot_direct_writer::sleb(enc, pval as! i32);
                            }
                            g.module.text.append(enc[..]);
                            let d = enc.len - 1;
                            if d != 0 {
                                patch_offs.push(poff);
                                patch_deltas.push(d);
                            }
                            cursor = poff + 1;
                        }
                        if cursor < body_len { g.module.text.append(pkt[body_pos + cursor..body_pos + body_len]); }
                    }
                    let final_body_len = g.module.text.len - body_start;
                    let fn_idx = g.s.instances[id].function - (g.module.imports.len as u32);
                    g.module.functions[fn_idx].body = blot_direct_writer::Range { start: body_start, len: final_body_len };
                    if g.s.track_deps {
                        let dep_start = g.s.dep_list.len as u32;
                        var dpos = deps_pos;
                        for di in 0..deps_len {
                            var dep_id = binary::u32le(pkt, dpos);
                            dpos += 4;
                            if (dep_id & 0x80000000) != 0 {
                                dep_id = ev_insts[(dep_id & 0x7fffffff) as i64];
                            }
                            g.s.dep_list.push(dep_id);
                        }
                        g.s.instances[id].deps_start = dep_start;
                        g.s.instances[id].deps_len = deps_len as u32;
                        var ipos = inl_pos;
                        for ii in 0..inl_len {
                            g.s.inlined_callees.put(binary::u64le(pkt, ipos), 1);
                            ipos += 8;
                        }
                    }
                    if recording {
                        var spos = sites_pos;
                        for si in 0..sites_len {
                            let sunit = binary::u32le(pkt, spos);
                            let snode = binary::u32le(pkt, spos + 4);
                            var soff = binary::u64le(pkt, spos + 8) as! i64;
                            spos += 16;
                            if soff >= 0 && patch_offs.len != 0 {
                                var adj: i64 = 0;
                                for pdi in 0..patch_offs.len {
                                    if patch_offs[pdi] < soff { adj += patch_deltas[pdi]; }
                                    else { break; }
                                }
                                soff += adj;
                            }
                            blot_direct_relocations::pushBodySite(blot_direct_relocations::Site { sunit, snode, soff }, fn_idx, body_start);
                        }
                    }
                    g.s.instances[id].emitted = true;
                    applied = true;
                    applied_count += 1;
                }
            }
        }
        if !applied {
            g.s.instances[id].emitted = true;
            let error = blot_direct_function::emitInstance(g, id);
            if error != blot_direct_types::Error.none { wave_err = error; break; }
        }
    }
    return wave_err, applied_count;
}

fn emitAll(g: Generator&) -> Error {
    var next: i64 = 0;
    let workers = blot_direct_writer::emitWorkers();
    var allow_parallel = workers > 1 && blot_native::platform_is_linux() != 0 && !g.s.replaying;
    var pool_width: i64 = 0;
    if allow_parallel {
        var total_core_nodes: i64 = 0;
        for u in g.units { total_core_nodes += u.nodes.len; }
        if total_core_nodes < 250000 {
            allow_parallel = false;
        } else {
            pool_width = min(workers as i64, min(12, max(6, total_core_nodes / 80000)));
            if pool_width <= 1 { allow_parallel = false; }
        }
    }
    var pool = EmitPool {};
    var sync_buf: u8[>..<] = [];
    var all_lanes: u8[>..<] = [];
    var job_off: i64[>..<] = [];
    var job_len: i64[>..<] = [];
    var ev_vals: u32[>..<] = [];
    var ev_insts: u32[>..<] = [];
    var u32_buf: u32[>..] = [];
    var fld_buf: blot_direct_types::Field[>..] = [];
    var eu: u32[>..<] = [];
    var et: u32[>..<] = [];
    var ev: Ty[>..<] = [];
    var ptmp: Ty[>..<] = [];
    var patch_offs: i64[>..<] = [];
    var patch_deltas: i64[>..<] = [];
    var enc: u8[>..<] = [];
    var failed_waves: i64 = 0;
    var result_err = blot_direct_types::Error.none;
    while next < g.s.queue.len {
        if allow_parallel {
            let pending = g.s.queue.len - next;
            let need = if pool.handle != 0 { max(12, pool_width * 2) } else { 64 };
            if pending >= need {
                if pool.handle != 0 && (
                    pool.has_rt != g.s.has_rt ||
                    pool.has_memory != g.module.has_memory ||
                    pool.host_slots != g.module.host_slots ||
                    pool.exported_storage != g.s.exported_storage
                ) {
                    closeEmitPool(pool);
                }
                if pool.handle == 0 {
                    if !openEmitPool(g, pool, pool_width) {
                        allow_parallel = false;
                    }
                }
                if pool.handle != 0 {
                    let take = min(pending, 16384);
                    let wave_start = next;
                    next += take;
                    let werr, applied = emitWavePool(
                        g, pool, wave_start, next, sync_buf, all_lanes, job_off, job_len,
                        ev_vals, ev_insts, u32_buf, fld_buf, eu, et, ev, ptmp,
                        patch_offs, patch_deltas, enc
                    );
                    if werr != blot_direct_types::Error.none { result_err = werr; break; }
                    if applied == 0 {
                        failed_waves += 1;
                        if failed_waves >= 2 {
                            closeEmitPool(pool);
                            allow_parallel = false;
                        }
                    } else {
                        failed_waves = 0;
                    }
                    continue;
                }
            }
        }
        let id = g.s.queue[next];
        next += 1;
        if g.s.instances[id].emitted { continue; }
        g.s.instances[id].emitted = true;
        let error = blot_direct_function::emitInstance(g, id);
        if error != blot_direct_types::Error.none { result_err = error; break; }
    }
    closeEmitPool(pool);
    return result_err;
}
