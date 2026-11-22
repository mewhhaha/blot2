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
import check.core;
import check.types;
import check.diagnostic_code;
import check.storage_types;
import check.wire_schema;
import direct.writer;
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
    var h = ::hash(kindCode(key.kind));
    h = ::hash_combine(h, ::hash(key.unit));
    h = ::hash_combine(h, ::hash(key.id));
    h = ::hash_combine(h, ::hash(key.ty));
    h = ::hash_combine(h, ::hash(key.parent));
    if key.evidence_context == 0 { return h; }
    return ::hash_combine(h, ::hash(key.evidence_context));
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
    // The local that allows iteration releases (no memory-holding value was
    // stored during the body), and the carried owner slots that must
    // predate the iteration for a release to be safe.
    allow: u32 = 0,
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
    kernels: blot_check_wire_schema::KernelInfo[>..] = [],
    processes: blot_check_wire_schema::ProcessInfo[>..] = [],
    wire_word_tags: u8[>..] = [],
    sparks_vectorized: i64 = 0,
    sparks_scalar_fallback: i64 = 0,
}

fn recordDep(g: Generator&, id: u32) {
    if !g.s.track_deps || g.s.active_instance == 0xffffffff { return; }
    for at in g.s.dep_frame_mark..g.s.dep_scratch.len {
        if g.s.dep_scratch[at].id == id { return; }
    }
    g.s.dep_scratch.push(DepEntry { id });
}
fn recordInlined(g: Generator&, unit: u32, binding: u32) {
    if g.s.track_deps { g.s.inlined_callees.put(key64(unit, binding), 1); }
}

fn resetUnitCaches(s: State&, unit_id: u32) {
    let idx = (unit_id - 1) as i64;
    if idx < s.use_count_base.len { s.use_count_base[idx] = 0xffffffff; }
    if idx < s.quantified_base.len { s.quantified_base[idx] = 0xffffffff; }
    if idx < s.captured_base.len { s.captured_base[idx] = 0xffffffff; }
    s.dispatch_cache.clear();
}

fn resetAllCaches(s: State&) {
    for i in 0..s.use_count_base.len { s.use_count_base[i] = 0xffffffff; }
    for i in 0..s.quantified_base.len { s.quantified_base[i] = 0xffffffff; }
    for i in 0..s.captured_base.len { s.captured_base[i] = 0xffffffff; }
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
        boolean => { return NominalIdentity { 0, blot_check_types::boolean }, true; },
        unit => { return NominalIdentity { 0, blot_check_types::unit }, true; },
        array => { return NominalIdentity { 0, 0xffffffff }, true; },
        // Storage capabilities are compiler-owned nominal identities.
        grow => { return NominalIdentity { 0xffffffff, blot_check_storage_types::grow }, true; },
        resize => { return NominalIdentity { 0xffffffff, blot_check_storage_types::resize }, true; },
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
        return g.module.signature(small[..parameter_words.len + 1], result_words), blot_direct_types::Error.none;
    }
    var words: ValType[>..<] = [];
    words.push(blot_direct_writer::VT_i32);
    words.append(parameter_words);
    return g.module.signature(words[..], result_words), blot_direct_types::Error.none;
}
fn find(g: Generator&, key: InstanceKey) -> u32, bool {
    let head, known = g.s.instance_index.get(hashKey(key));
    var at = head;
    while at != 0 {
        let entry = g.s.index_nodes[at - 1];
        if sameKey(entry.key, key) {
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
fn runtime_(g: Generator&) -> const Runtime& {
    if !g.s.has_rt {
        g.s.rt = blot_direct_runtime::emitWithFork(g.module, blot_direct_runtime::Budgets {}, unitsHaveFork(g.units));
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
        while g.s.contents_memory.len < g.types.nodes.len { g.s.contents_memory.push(0); }
    }
    // A recursive type's flat form is a pointer into scope memory.
    let is_recursive, recursive_error = g.types.isRecursive(ty);
    if recursive_error == blot_direct_types::Error.none && is_recursive { return true, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    var result = false;
    match n.tag {
        unit, boolean, u32_, f32_, never => {},
        function, provider, array, grow, resize, ref, view, link, cell => { result = true; },
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
        while g.s.holds_memory.len < g.types.nodes.len { g.s.holds_memory.push(0); }
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
        unit, boolean, u32_, f32_, never => {},
        function, provider, array, grow, resize, ref, view, link, cell => { result = true; },
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
    let id = g.s.operation_ids.count + 1;
    g.s.operation_ids.put(operation, id);
    return id;
}
recursive fn propagateObligations(g: Generator&, m: const Module&, obligations: const blot_check_types::List[:], mark: i64, depth: i64) {
    let s .= g.s;
    var grew = true;
    while grew {
        grew = false;
        for span in obligations {
            for at in 0..(span.len as i64) {
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
                    continue;
                }
                if goal.kind == blot_check_types::ObligationKind.callee_use {
                    if depth >= 16 { continue; }
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
                    if cbody { cobs[1] = cbody.scheme.obligations; }
                    propagateObligations(g, m, cobs[..], cmark, depth + 1);
                    var reached: bool[64] = [false; 64];
                    for pi in 0..count_p { reached[pi] = within(g, m, pvar_ids[pi], cmark); }
                    s.scratch.resize(cmark);
                    let before = s.scratch.len;
                    for pi in 0..count_p {
                        if reached[pi] { mentions(g, m, arg_ids[pi], mark, 0); }
                    }
                    if s.scratch.len != before { grew = true; }
                    continue;
                }
                if goal.result == 0 || (goal.kind != blot_check_types::ObligationKind.field && goal.kind != blot_check_types::ObligationKind.writable_field && goal.kind != blot_check_types::ObligationKind.collection && goal.kind != blot_check_types::ObligationKind.update) { continue; }
                if !within(g, m, goal.ty, mark) { continue; }
                let before = s.scratch.len;
                mentions(g, m, goal.result, mark, 0);
                mentions(g, m, goal.other, mark, 0);
                mentions(g, m, goal.signature, mark, 0);
                if s.scratch.len != before { grew = true; }
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
        for at in 0..m.types.nodes.len { g.s.quantified_vals.push(0); }
        let s .= g.s;
        let mark = s.scratch.len;
        for index in 0..m.bindings.len {
            let binding = m.bindings[index];
            let body .= m.body(index as u32);
            s.scratch.resize(mark);
            mentions(g, m, binding.ty, mark, 0);
            var obligations: blot_check_types::List[2] = [binding.scheme.obligations, blot_check_types::List {}];
            if body { obligations[1] = body.scheme.obligations; }
            // Obligations on reachable receivers reach their results.
            propagateObligations(g, m, obligations[..], mark, 0);
            var schemes: blot_check_types::List[2] = [binding.scheme.variables, blot_check_types::List {}];
            if body { schemes[1] = body.scheme.variables; }
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
    var pass: i64 = 0;
    while pass <= count {
        let before = env.count;
        for at in 0..count {
            let goal = m.obligations[goals_span.start + at];
            if goal.kind == blot_check_types::ObligationKind.type_eq {
                let left, lerr = g.types.lower(m, goal.ty, env);
                if lerr == blot_direct_types::Error.none {
                    g.types.match_(m, goal.other, left, env);
                } else {
                    let right, rerr = g.types.lower(m, goal.other, env);
                    if rerr == blot_direct_types::Error.none { g.types.match_(m, goal.ty, right, env); }
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
            if goal.kind != blot_check_types::ObligationKind.field && goal.kind != blot_check_types::ObligationKind.writable_field && goal.kind != blot_check_types::ObligationKind.collection { continue; }
            let receiver, error = g.types.lower(m, goal.ty, env);
            if error != blot_direct_types::Error.none { continue; }
            let n = g.types.node(receiver);
            if goal.kind == blot_check_types::ObligationKind.collection {
                match n.tag {
                    array, grow, resize, view => { g.types.match_(m, goal.result, n.a, env); },
                    _ => {},
                }
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
            if arrow.tag == blot_direct_types::Tag.function { g.types.match_(m, goal.result, arrow.b, env); }
        }
        if env.count == before { return blot_direct_types::Error.none; }
        pass += 1;
    }
    return blot_direct_types::Error.none;
}

fn emitAll(g: Generator&) -> Error {
    var next: i64 = 0;
    while next < g.s.queue.len {
        let id = g.s.queue[next];
        next += 1;
        if g.s.instances[id].emitted { continue; }
        g.s.instances[id].emitted = true;
        let error = blot_direct_function::emitInstance(g, id);
        if error != blot_direct_types::Error.none { return error; }
    }
    return blot_direct_types::Error.none;
}
