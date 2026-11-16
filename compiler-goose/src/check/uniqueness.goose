// Uniqueness of `:=` paths through storage (tasks/MEMORY_MODEL.md, rules 4
// and 5; compiler/src/check/uniqueness.zig). A path update that reaches
// storage writes in place, which is only the successor semantics of `:=` when
// nothing else can observe the old root. This pass proves that inside one
// body and rejects the rest with `aliased_update`. One fact crosses a call:
// a named function may take over a parameter (`own`). That parameter is
// unique all the way down inside the function, so the call requires an
// argument nothing else holds, and the name it was passed by is spent: a
// later read of it is `spent_value`. In return, such a function's result is
// the caller's alone: each of its returns must give a value nothing else
// holds (`result_not_owned`), and the call's result is unique.
//
// Facts belong to binding versions and follow evaluation order. A version is
// unique after it is bound to a fresh allocation, stays unique across its own
// `:=` updates, and stops being unique once the same version escapes: bound
// to another name, captured, passed, placed in an aggregate, returned or
// broken out, or read out as a storage-holding element or field. Branches
// meet their arms through an undo trail; an arm that leaves the function
// contributes nothing. Each loop body is first probed with its carries'
// incoming facts, then checked once with the carries met with that probe's
// backedges; nested loops are probed by a single pass, so a body is visited
// once more per enclosing loop.
//
// A local's value moves at the local's last use: bound to another name,
// placed in a record, an array or a constructor, returned or broken out, the
// new holder takes the local's fact, because nothing reads the local again.
// Each body is first walked once without judging it, only to log every read
// of a local in evaluation order; the last read on each path is a last use.
//
// The walk is recursive, so every table lives in the Analyzer that `check`
// owns. What the Zig source keeps in a local list during one visit (a
// record's entries, a path's fields, a loop's carry facts, a branch's
// changed bindings) is a run on one of the Analyzer's stacks here, popped
// before the visit returns.
namespace blot_check_uniqueness;
import std;
import dictionary;
import check.core;
import check.types;
import check.storage_types;
import check.storage_ops;
import eval.body_recipe;
import backend.collection_ops;
import support.error;
import support.option;
import support.native;

type Module = blot_check_core::Module;
type UpdateStep = blot_check_core::UpdateStep;
type LoopCarry = blot_check_core::LoopCarry;
type Merge = blot_check_core::Merge;

// `none`: something else may observe it. `shell`: its own storage is unique,
// but storage held by its elements may be shared. `deep`: it and all storage
// reachable inside it are unique. Larger values name record facts, whose
// fields have facts of their own. `top` only seeds a meet.
type Fact = u32;
let none: Fact = 0;
let shell: Fact = 1;
let deep: Fact = 2;
let first_record: Fact = 3;
let top: Fact = 0xffffffff;
// The version was passed to an `own` parameter: its storage belongs to that
// call, which may have written it in place. Below every other fact.
let spent: Fact = 0xfffffffe;

struct Entry { field: u32, fact: Fact }
// A record's facts by field symbol, sorted; unlisted fields have `default_`.
struct Record { default_: Fact, start: u32, len: u32 }
struct Change { binding: u32, old: Fact }
// An expression's result: the fact of a fresh value, or the version whose
// storage it may alias. `exits` means control only leaves the function.
struct Value { fact: Fact = 0, origin: u32 = 0, exits: bool = false }
// A loop being visited: its carries' continue facts, then their break facts,
// at `start` in the shared `carried` stack.
struct LoopFrame { id: u32, start: i64, len: i64 }
struct BlockFrame { id: u32, fact: Fact = 0xffffffff, broken: bool = false }
// A member of a type that takes over a parameter: `value.member` reaches it.
struct MemberTaker { identity: blot_check_types::NominalIdentity, member: u32, taking: u64 }
struct Rejection { node: u32, span: blot_check_core::Span, code: blot_check_core::Code = blot_check_core::Code.aliased_update }
// A nominal being expanded, with whether each type argument holds storage.
struct Expansion { unit: u32, decl: u32, arguments: bool[16], len: i64 }
// The local version a projection chain starts from, and its fields.
struct Place { binding: u32 = 0, fields: u32[8] = [0; 8], len: i64 = 0 }
// A binding some arm of the branch being joined changed: the meet of its
// facts over those arms, how many arms changed it and the last one that did.
// `previous` is what `changed_slot` held before this entry.
struct Changed { binding: u32, fact: Fact, arms: i64, last: i64, previous: i64 }
// The meet of a branch's arms. Each arm runs from the same trail mark; an
// arm that leaves the function contributes nothing. The join's changed
// bindings start at `changed_start` on the Analyzer's `changed` stack and
// its merge facts at `merged_start` on `merged`.
struct Join {
    // Where this arm's reads start in the dry run's log.
    log: i64 = 0,
    base: i64,
    merges: const Merge[:],
    falls: i64 = 0,
    value: Fact = 0xffffffff,
    exits: bool = true,
    changed_start: i64,
    merged_start: i64
}

root struct Analyzer {
    facts: Fact[>..] = [],
    // Per binding: the innermost loop around its definition, or 0, and the
    // root of the function or closure that defines it.
    born: u32[>..] = [],
    home: u32[>..] = [],
    // The dry run: every read of a local, as (binding, node) pairs in
    // evaluation order, and the nodes that are a local's last read.
    dry: bool = false,
    reads: u32[>..<] = [],
    last_read: bool[>..] = [],
    stamp: u32[>..] = [],
    generation: u32 = 0,
    trail: Change[>..<] = [],
    records: Record[>..] = [],
    entries: Entry[>..] = [],
    holds_cache: dictionary<u32, u8> = dictionary<u32, u8> {},
    nominal_index: dictionary<u64, u32> = dictionary<u64, u32> {},
    expanding: Expansion[>..<] = [],
    loops: LoopFrame[>..<] = [],
    carried: Fact[>..<] = [],
    blocks: BlockFrame[>..<] = [],
    function_roots: u32[>..<] = [],
    rejections: Rejection[>..<] = [],
    children: u32[>..<] = [],
    // Entries of the record fact being built.
    scratch: Entry[>..<] = [],
    // Field symbols of the path being updated.
    fields: u32[>..<] = [],
    // Per loop: its carries' incoming, assumed, result and outgoing facts.
    loop_facts: Fact[>..<] = [],
    // Per join: the bindings its arms changed, and for each binding the
    // index of its entry in the innermost join that has one, or -1.
    changed: Changed[>..<] = [],
    changed_slot: i64[>..] = [],
    // Per join: one fact per branch merge.
    merged: Fact[>..<] = [],
    // While positive, loop bodies are only probed: rejections are dropped.
    probing: u32 = 0,
    // The functions that take over a parameter, by unit and binding: the
    // parameter mask, and above it how many arguments a call gives.
    takers: dictionary<u64, u64> = dictionary<u64, u64> {},
    member_takers: MemberTaker[>..] = [],
    // Phase 2 for every function, while it is being measured (set by the
    // environment variable BLOT_BORROWED_RULES; tasks/MEMORY_MODEL.md): each
    // function's result is its caller's alone, a call only borrows its
    // arguments, and a type variable holds no array.
    rules: bool = false,
    owns_cache: dictionary<u32, u8> = dictionary<u32, u8> {},
    // Under the rules: each binding by unit and number; whether it is a
    // generic function that returns what it was lent (0 unknown, 1 no,
    // 2 yes) and how many arguments its type takes; and each member of a
    // type by the type and the member's name.
    binding_index: dictionary<u64, u32> = dictionary<u64, u32> {},
    reader_state: u8[>..] = [],
    reader_arity: u8[>..] = [],
    identity_ids: dictionary<u64, u32> = dictionary<u64, u32> {},
    members: dictionary<u64, u32> = dictionary<u64, u32> {},
    lends_cache: dictionary<u32, u8> = dictionary<u32, u8> {},
    // The root of the function being checked when its result must be owned.
    owned_result: u32 = 0,
    // Blocks whose value is the function's result: `return do: ...`.
    tails: u32[>..<] = []
}

// Appends one diagnostic per rejected `:=`, `own` argument and read of a
// spent name in `module`.
fn check(module: const Module&, out: blot_check_core::Diagnostic[>..<]&) {
    var analyzer = Analyzer { .. };
    for binding in module.bindings {
        let parameters = binding.capability_parameters;
        if parameters.own == 0 { continue; }
        analyzer.takers.insert(((binding.target.unit as u64) << 32) | binding.target.binding, ((parameters.own_count as u64) << 32) | parameters.own);
    }
    {
        let name = "BLOT_BORROWED_RULES\0";
        analyzer.rules = blot_native::environment_size(name[0]) >= 0;
    }
    if module.updates.len == 0 && analyzer.takers.count == 0 && !analyzer.rules { return; }
    if analyzer.rules {
        for binding, index in module.bindings {
            analyzer.reader_state.push(0);
            analyzer.reader_arity.push(0);
            if index != 0 { analyzer.binding_index.insert(((binding.target.unit as u64) << 32) | binding.target.binding, index as! u32); }
        }
        for method in module.associated {
            if method.member == 0 { continue; }
            let found .= analyzer.binding_index.get(((method.target.unit as u64) << 32) | method.target.binding);
            if !found { continue; }
            let index: u32 = found;
            let key = ((method.identity.unit as u64) << 32) | method.identity.decl;
            var identity_id = analyzer.identity_ids.count as u32 + 1;
            let known .= analyzer.identity_ids.get(key);
            if known { let existing: u32 = known; identity_id = existing; } else { analyzer.identity_ids.insert(key, identity_id); }
            analyzer.members.insert(((identity_id as u64) << 32) | method.member, index);
        }
    }
    if analyzer.takers.count != 0 {
        for method in module.associated {
            let found .= analyzer.takers.get(((method.target.unit as u64) << 32) | method.target.binding);
            if !found { continue; }
            let taking: u64 = found;
            analyzer.member_takers.push(MemberTaker { identity: method.identity, member: method.member, taking: taking });
        }
    }
    for at in 0..module.bindings.len { analyzer.facts.push(none); analyzer.born.push(0); analyzer.home.push(0); analyzer.stamp.push(0); analyzer.changed_slot.push(-1); }
    for at in 0..module.nodes.len { analyzer.last_read.push(false); }
    for body, index in module.bodies {
        if index == 0 || body.root == 0 { continue; }
        // An `own` parameter arrives unique all the way down: every call
        // names this function and gives up an argument that was.
        let own = module.bindings[body.binding].capability_parameters.own;
        for parameter, position in module.bodyParameters(body) {
            if !local(analyzer, parameter.binding) { continue; }
            analyzer.home[parameter.binding] = body.root;
            if own != 0 && body.is_function && position < 32 && (own >> (position as! u32)) & 1 != 0 { set(analyzer, parameter.binding, deep); }
        }
        analyzer.owned_result = 0;
        if (own != 0 || analyzer.rules) && body.is_function { analyzer.owned_result = body.root; }
        analyzer.function_roots.push(body.root);
        // The dry run: log the reads, judge nothing, keep no fact.
        {
            let mark = analyzer.trail.len;
            analyzer.dry = true;
            analyzer.probing += 1;
            analyzer.reads.resize(0);
            visit(analyzer, module, body.root);
            lastReads(analyzer, 0);
            analyzer.probing -= 1;
            analyzer.dry = false;
            undo(analyzer, mark);
        }
        let value = visit(analyzer, module, body.root);
        if analyzer.owned_result != 0 && !value.exits { ownedResult(analyzer, module, body.root, value); }
        escape(analyzer, value);
        analyzer.function_roots.resize(analyzer.function_roots.len - 1);
    }
    sort(analyzer.rejections[..]) { a, b => a.node < b.node }
    var previous: u32 = 0;
    for rejection in analyzer.rejections {
        if rejection.node == previous { continue; }
        previous = rejection.node;
        out.push(blot_check_core::Diagnostic { code: rejection.code, span: rejection.span });
    }
}

// ---- Facts -------------------------------------------------------------

fn local(self_: const Analyzer&, binding: u32) -> bool { return binding != 0 && binding < self_.facts.len; }
fn set(self_: Analyzer&, binding: u32, fact: Fact) {
    if !local(self_, binding) || self_.facts[binding] == fact { return; }
    self_.trail.push(Change { binding: binding, old: self_.facts[binding] });
    self_.facts[binding] = fact;
}
// A spent version stays spent: nothing gives its storage back.
fn kill(self_: Analyzer&, binding: u32) { if local(self_, binding) && self_.facts[binding] == spent { return; } set(self_, binding, none); }
// Sets the fact of a version at its definition.
fn define(self_: Analyzer&, binding: u32, fact: Fact) {
    if local(self_, binding) {
        var loop_id: u32 = 0;
        if self_.loops.len != 0 { loop_id = self_.loops[self_.loops.len - 1].id; }
        self_.born[binding] = loop_id;
        if self_.function_roots.len != 0 { self_.home[binding] = self_.function_roots[self_.function_roots.len - 1]; }
    }
    set(self_, binding, fact);
}
// A read of `binding` at `node`, for the dry run.
fn read(self_: Analyzer&, binding: u32, node: u32) {
    if self_.dry && local(self_, binding) { self_.reads.push(binding); self_.reads.push(node); }
}
// Marks the last read of each local among the reads logged since `start`.
// Nothing reads the local after it: the function ends there, or the log
// does.
fn lastReads(self_: Analyzer&, start: i64) {
    self_.generation += 1;
    var at = self_.reads.len;
    while at > start {
        at -= 2;
        let binding = self_.reads[at];
        if self_.stamp[binding] == self_.generation { continue; }
        self_.stamp[binding] = self_.generation;
        self_.last_read[self_.reads[at + 1]] = true;
    }
}
// Whether the value read at `node` moves out of `binding`: `node` names the
// local, is its last read, and runs once for each definition of it.
fn moves(self_: const Analyzer&, m: const Module&, node: u32, binding: u32) -> bool {
    if self_.dry || !local(self_, binding) || m.node(node).tag != blot_check_core::Tag.reference || !self_.last_read[node] { return false; }
    var loop_id: u32 = 0;
    if self_.loops.len != 0 { loop_id = self_.loops[self_.loops.len - 1].id; }
    if self_.born[binding] != loop_id || self_.function_roots.len == 0 { return false; }
    return self_.home[binding] == self_.function_roots[self_.function_roots.len - 1];
}
// The fact the holder of `value` gets, where `node` computed it: a fresh
// value's own fact, a moved local's fact, or none for an alias, which also
// ends the uniqueness of the version it aliases.
fn taken(self_: Analyzer&, m: const Module&, node: u32, value: Value) -> Fact {
    if value.origin == 0 { return value.fact; }
    if moves(self_, m, node, value.origin) {
        let fact = self_.facts[value.origin];
        kill(self_, value.origin);
        return fact;
    }
    escape(self_, value);
    return none;
}
fn reject(self_: Analyzer&, m: const Module&, node: u32, code: blot_check_core::Code) {
    if self_.probing == 0 { self_.rejections.push(Rejection { node: node, span: m.span(node), code: code }); }
}
fn escape(self_: Analyzer&, value: Value) { if value.origin != 0 { kill(self_, value.origin); } }
fn undo(self_: Analyzer&, mark: i64) {
    while self_.trail.len > mark {
        let change = self_.trail[self_.trail.len - 1];
        self_.trail.resize(self_.trail.len - 1);
        self_.facts[change.binding] = change.old;
    }
}
fn unique(fact: Fact) -> bool { return fact == shell || fact == deep; }
fn record(self_: const Analyzer&, fact: Fact) -> Record { return self_.records[fact - first_record]; }
fn field(self_: const Analyzer&, fact: Fact, symbol: u32) -> Fact {
    if fact < first_record { if fact == deep { return deep; } return none; }
    let value = record(self_, fact);
    for at in 0..value.len { let entry = self_.entries[value.start + at]; if entry.field == symbol { return entry.fact; } }
    return value.default_;
}
// A record fact from the sorted entries at `scratch[from..]`; plain facts
// when no field differs. The caller pops the entries.
fn makeRecord(self_: Analyzer&, default_: Fact, from: i64) -> Fact {
    var differs = false;
    for at in from..self_.scratch.len { differs = differs || self_.scratch[at].fact != default_; }
    if !differs { return default_; }
    let start = self_.entries.len as! u32;
    let count = (self_.scratch.len - from) as! u32;
    for at in from..self_.scratch.len { let entry = self_.scratch[at]; self_.entries.push(entry); }
    self_.records.push(Record { default_: default_, start: start, len: count });
    return first_record + (self_.records.len - 1) as! u32;
}
// Adds `entry` to the entries at `scratch[mark..]`, which stay sorted by
// field. No two of them share a field.
fn pushSorted(self_: Analyzer&, mark: i64, entry: Entry) {
    self_.scratch.push(entry);
    var at = self_.scratch.len - 1;
    while at > mark && self_.scratch[at].field < self_.scratch[at - 1].field {
        let moved = self_.scratch[at - 1];
        self_.scratch[at - 1] = self_.scratch[at];
        self_.scratch[at] = moved;
        at -= 1;
    }
}
fn withField(self_: Analyzer&, fact: Fact, symbol: u32, replacement: Fact) -> Fact {
    let mark = self_.scratch.len;
    var default_: Fact = none;
    if fact == deep { default_ = deep; }
    if fact >= first_record {
        let value = record(self_, fact);
        default_ = value.default_;
        for at in 0..value.len { let entry = self_.entries[value.start + at]; self_.scratch.push(entry); }
    }
    var found = false;
    for at in mark..self_.scratch.len {
        if self_.scratch[at].field == symbol { self_.scratch[at].fact = replacement; found = true; break; }
    }
    if !found { pushSorted(self_, mark, Entry { field: symbol, fact: replacement }); }
    let result = makeRecord(self_, default_, mark);
    self_.scratch.resize(mark);
    return result;
}
recursive fn meet(self_: Analyzer&, left: Fact, right: Fact) -> Fact {
    if left == top { return right; }
    if right == top { return left; }
    if left == right { return left; }
    if left == spent || right == spent { return spent; }
    if left == none || right == none { return none; }
    if left < first_record && right < first_record { return min(left, right); }
    // A record meets `deep` as itself; a record never has a `shell`.
    if left == deep { return right; }
    if right == deep { return left; }
    if left == shell || right == shell { return none; }
    let l = record(self_, left);
    let r = record(self_, right);
    // Nested meets append entries and records, never change them: both
    // records are read in place while the merged entries collect on scratch.
    let mark = self_.scratch.len;
    var i: u32 = 0;
    var j: u32 = 0;
    while i < l.len || j < r.len {
        if j == r.len || (i < l.len && self_.entries[l.start + i].field < self_.entries[r.start + j].field) {
            let entry = self_.entries[l.start + i];
            let fact = meet(self_, entry.fact, r.default_);
            self_.scratch.push(Entry { field: entry.field, fact: fact });
            i += 1;
        } else if i == l.len || self_.entries[r.start + j].field < self_.entries[l.start + i].field {
            let entry = self_.entries[r.start + j];
            let fact = meet(self_, l.default_, entry.fact);
            self_.scratch.push(Entry { field: entry.field, fact: fact });
            j += 1;
        } else {
            let a = self_.entries[l.start + i];
            let b = self_.entries[r.start + j];
            let fact = meet(self_, a.fact, b.fact);
            self_.scratch.push(Entry { field: a.field, fact: fact });
            i += 1;
            j += 1;
        }
    }
    let default_ = meet(self_, l.default_, r.default_);
    let result = makeRecord(self_, default_, mark);
    self_.scratch.resize(mark);
    return result;
}
recursive fn same(self_: const Analyzer&, left: Fact, right: Fact) -> bool {
    if left == right { return true; }
    if left < first_record || right < first_record || left >= spent || right >= spent { return false; }
    let l = record(self_, left);
    let r = record(self_, right);
    if !same(self_, l.default_, r.default_) || l.len != r.len { return false; }
    for at in 0..l.len {
        let a = self_.entries[l.start + at];
        let b = self_.entries[r.start + at];
        if a.field != b.field || !same(self_, a.fact, b.fact) { return false; }
    }
    return true;
}

// ---- Types -------------------------------------------------------------

// Whether a value of `ty` can hold storage. Unknown shapes can.
fn holds(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    let known, cached = holdsKnown(self_, ty);
    if cached { return known; }
    let result = holdsIn(self_, m, ty, [], [], 0);
    var bit: u8 = 0;
    if result { bit = 1; }
    self_.holds_cache.insert(ty, bit);
    return result;
}
fn holdsKnown(self_: Analyzer&, ty: u32) -> bool, bool {
    let known .= self_.holds_cache.get(ty);
    if !known { return false, false; }
    let bit: u8 = known;
    return bit != 0, true;
}
recursive fn holdsIn(self_: Analyzer&, m: const Module&, ty: u32, variables: const u32[:], arguments: const bool[:], depth: i64) -> bool {
    if ty == blot_check_types::unit || ty == blot_check_types::boolean || ty == blot_check_types::u32_type || ty == blot_check_types::f32_type || ty == blot_check_types::never { return false; }
    if depth > 64 || ty >= m.types.nodes.len { return true; }
    for variable, at in variables { if variable == ty { return arguments[at]; } }
    if variables.len == 0 {
        let known, cached = holdsKnown(self_, ty);
        if cached { return known; }
    }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return false; }
    // Inside a generic body a type variable is plain data.
    if self_.rules && (n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound) { return false; }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.function { return true; }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) {
            if holdsIn(self_, m, item, variables, arguments, depth + 1) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b {
            if holdsIn(self_, m, m.types.recordField(n, index).ty, variables, arguments, depth + 1) { return true; }
        }
        return false;
    }
    if n.tag != blot_check_types::Tag.nominal { return true; }
    if blot_check_storage_types::identity(n.a, n.b).present || n.a == 0xffffffff { return true; }
    let index, found = nominalIndex(self_, m, n.a, n.b);
    if !found { return true; }
    let nominal = m.nominal(index);
    if nominal.is_opaque { return true; }
    let own = m.types.list(nominal.variables);
    let given = m.types.nominalArguments(n);
    if own.len != given.len || own.len > 16 { return true; }
    var bits: bool[16] = [false; 16];
    for argument, at in given { bits[at] = holdsIn(self_, m, argument, variables, arguments, depth + 1); }
    // A recursive occurrence at the same arguments adds no storage its
    // first expansion lacks; one at other arguments might.
    for outer in self_.expanding {
        if outer.unit == n.a && outer.decl == n.b {
            if outer.len != own.len { return true; }
            for at in 0..own.len { if outer.arguments[at] != bits[at] { return true; } }
            return false;
        }
    }
    self_.expanding.push(Expansion { unit: n.a, decl: n.b, arguments: bits, len: own.len });
    var result = false;
    for constructor in m.nominalConstructors(index) {
        let payload = m.constructor(constructor).payload;
        if payload != 0 && holdsIn(self_, m, payload, own, bits[..own.len], depth + 1) { result = true; break; }
    }
    self_.expanding.resize(self_.expanding.len - 1);
    return result;
}
// Whether a value of `ty` can hold an array it owns (`want_owned`), or a
// part that only borrows: a view, a reference, a link, a cursor or a
// function. Type variables do neither. A shape this cannot read (an opaque
// type, an effect type) counts as borrowing: its results are not checked
// and not promised.
fn owns(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    let known .= self_.owns_cache.get(ty);
    if known { let bit: u8 = known; return bit != 0; }
    let result = partsIn(self_, m, ty, true, [], [], 0);
    var bit: u8 = 0;
    if result { bit = 1; }
    self_.owns_cache.insert(ty, bit);
    return result;
}
fn lends(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    let known .= self_.lends_cache.get(ty);
    if known { let bit: u8 = known; return bit != 0; }
    let result = partsIn(self_, m, ty, false, [], [], 0);
    var bit: u8 = 0;
    if result { bit = 1; }
    self_.lends_cache.insert(ty, bit);
    return result;
}
recursive fn partsIn(self_: Analyzer&, m: const Module&, ty: u32, want_owned: bool, variables: const u32[:], arguments: const bool[:], depth: i64) -> bool {
    if ty == blot_check_types::unit || ty == blot_check_types::boolean || ty == blot_check_types::u32_type || ty == blot_check_types::f32_type || ty == blot_check_types::never { return false; }
    if depth > 64 || ty >= m.types.nodes.len { return !want_owned; }
    for variable, at in variables { if variable == ty { return arguments[at]; } }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return false; }
    if n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound { return false; }
    if n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.function { return !want_owned; }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list {
        if want_owned { return true; }
        return partsIn(self_, m, n.a, want_owned, variables, arguments, depth + 1);
    }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) {
            if partsIn(self_, m, item, want_owned, variables, arguments, depth + 1) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b {
            if partsIn(self_, m, m.types.recordField(n, index).ty, want_owned, variables, arguments, depth + 1) { return true; }
        }
        return false;
    }
    if n.tag != blot_check_types::Tag.nominal { return !want_owned; }
    let storage = blot_check_storage_types::identity(n.a, n.b);
    if storage.present {
        let owner = storage.value == blot_check_storage_types::grow || storage.value == blot_check_storage_types::resize;
        if want_owned { return owner; }
        if !owner { return true; }
        let given = m.types.nominalArguments(n);
        if given.len != 1 { return !want_owned; }
        return partsIn(self_, m, given[0], want_owned, variables, arguments, depth + 1);
    }
    if n.a == 0xffffffff { return !want_owned; }
    let index, found = nominalIndex(self_, m, n.a, n.b);
    if !found { return !want_owned; }
    let nominal = m.nominal(index);
    if nominal.is_opaque { return !want_owned; }
    let own = m.types.list(nominal.variables);
    let given = m.types.nominalArguments(n);
    if own.len != given.len || own.len > 16 { return !want_owned; }
    var bits: bool[16] = [false; 16];
    for argument, at in given { bits[at] = partsIn(self_, m, argument, want_owned, variables, arguments, depth + 1); }
    // A recursive occurrence at the same arguments adds nothing its first
    // expansion lacks; one at other arguments might.
    for outer in self_.expanding {
        if outer.unit == n.a && outer.decl == n.b {
            if outer.len != own.len { return !want_owned; }
            for at in 0..own.len { if outer.arguments[at] != bits[at] { return !want_owned; } }
            return false;
        }
    }
    self_.expanding.push(Expansion { unit: n.a, decl: n.b, arguments: bits, len: own.len });
    var result = false;
    for constructor in m.nominalConstructors(index) {
        let payload = m.constructor(constructor).payload;
        if payload != 0 && partsIn(self_, m, payload, want_owned, own, bits[..own.len], depth + 1) { result = true; break; }
    }
    self_.expanding.resize(self_.expanding.len - 1);
    return result;
}
fn nominalIndex(self_: Analyzer&, m: const Module&, unit: u32, decl: u32) -> u32, bool {
    if self_.nominal_index.count == 0 {
        for nominal, index in m.nominals {
            self_.nominal_index.insert(((nominal.identity.unit as u64) << 32) | nominal.identity.decl, index as! u32);
        }
    }
    let known .= self_.nominal_index.get(((unit as u64) << 32) | decl);
    if !known { return 0, false; }
    let index: u32 = known;
    return index, true;
}
fn element(self_: const Analyzer&, m: const Module&, ty: u32) -> blot_support::Option<u32> {
    if ty == 0 || ty >= m.types.nodes.len { return blot_support::none<u32>(); }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.list { return blot_support::some<u32>(n.a); }
    return blot_check_storage_types::readableElement(m.types, ty);
}
fn elementHolds(self_: Analyzer&, m: const Module&, container: u32) -> bool {
    let inner = element(self_, m, container);
    if !inner.present { return true; }
    return holds(self_, m, inner.value);
}
// The fact of a fresh container of `ty` whose elements are fresh only when
// `elements_deep`.
fn freshContainer(self_: Analyzer&, m: const Module&, ty: u32, elements_deep: bool) -> Fact {
    if elements_deep || !elementHolds(self_, m, ty) { return deep; }
    return shell;
}

// ---- Places ------------------------------------------------------------

fn place(self_: const Analyzer&, m: const Module&, id: u32) -> Place, bool {
    var reverse: u32[8] = [0; 8];
    var count: i64 = 0;
    var cursor = id;
    loop {
        let n = m.node(cursor);
        if n.tag == blot_check_core::Tag.reference {
            let target = m.reference(cursor);
            if target.unit != 0 && target.unit != m.unit { return Place { .. }, false; }
            var result = Place { binding: target.binding, len: count, .. };
            for at in 0..count { result.fields[at] = reverse[count - 1 - at]; }
            return result, true;
        }
        if n.tag != blot_check_core::Tag.project || count == 8 { return Place { .. }, false; }
        reverse[count] = m.projection(n.b).field;
        count += 1;
        cursor = n.a;
    }
}
// `fact` with the storage at `fields` no longer known to own its elements:
// a store or push put a value there that may be shared.
recursive fn weaken(self_: Analyzer&, fact: Fact, fields: const u32[:]) -> Fact {
    if fields.len == 0 {
        if fact == deep { return shell; }
        if fact >= first_record { return none; }
        return fact;
    }
    let inner = weaken(self_, field(self_, fact, fields[0]), fields[1..]);
    return withField(self_, fact, fields[0], inner);
}
// After a value that may be shared is stored into the storage that `id` and
// the field steps of `selectors` before their first index select.
fn sharedInto(self_: Analyzer&, m: const Module&, id: u32, selectors: const UpdateStep[:]) {
    var target, found = place(self_, m, id);
    if !found || !local(self_, target.binding) { return; }
    for step in selectors {
        if step.kind == blot_check_core::UpdateKind.index { break; }
        if target.len == 8 { kill(self_, target.binding); return; }
        target.fields[target.len] = m.projection(step.projection).field;
        target.len += 1;
    }
    if self_.facts[target.binding] == spent { return; }
    let weakened = weaken(self_, self_.facts[target.binding], target.fields[..target.len]);
    set(self_, target.binding, weakened);
}

// ---- Visits ------------------------------------------------------------

recursive fn visitEscaping(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let value = visit(self_, m, id);
    escape(self_, value);
    return value;
}
recursive fn visitChildren(self_: Analyzer&, m: const Module&, id: u32) -> bool {
    let start = self_.children.len;
    {
        var list = blot_eval_body_recipe::Pending { items: self_.children, limit: 0x7fffffffffffffff };
        let error = blot_eval_body_recipe::appendChildren(list, m, id, false);
        assert(error == blot_error::Error.none);
    }
    var exits = false;
    var at = start;
    while at < self_.children.len {
        let child = self_.children[at];
        let value = visitEscaping(self_, m, child);
        exits = exits || value.exits;
        at += 1;
    }
    self_.children.resize(start);
    return exits;
}

recursive fn visit(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    if id == 0 || id >= m.nodes.len { return Value { .. }; }
    let n = m.node(id);
    let tag = n.tag;
    if tag == blot_check_core::Tag.constant || tag == blot_check_core::Tag.constructor_function || tag == blot_check_core::Tag.primitive_function || tag == blot_check_core::Tag.type_constructor || tag == blot_check_core::Tag.operation_value || tag == blot_check_core::Tag.invalid { return Value { .. }; }
    if tag == blot_check_core::Tag.panic { return Value { exits: true, .. }; }
    if tag == blot_check_core::Tag.reference {
        let target = m.reference(id);
        // A function that takes over a parameter is only ever called in
        // full, which `apply` and `call` see before this.
        if taker(self_, m, id) != 0 { reject(self_, m, id, blot_check_core::Code.own_function_value); return Value { .. }; }
        lentValue(self_, m, id);
        if target.unit != 0 && target.unit != m.unit { return Value { .. }; }
        if !local(self_, target.binding) { return Value { .. }; }
        read(self_, target.binding, id);
        if self_.facts[target.binding] == spent { reject(self_, m, id, blot_check_core::Code.spent_value); return Value { .. }; }
        return Value { origin: target.binding, .. };
    }
    if tag == blot_check_core::Tag.suite {
        var exits = false;
        for child in m.children(id) { let value = visit(self_, m, child); exits = value.exits || exits; }
        return Value { exits: exits, .. };
    }
    if tag == blot_check_core::Tag.block_ { return block_(self_, m, id); }
    if tag == blot_check_core::Tag.bind {
        let value = m.node(n.b);
        if value.tag == blot_check_core::Tag.update && !m.updateInfo(n.b).store { return update(self_, m, n.b, n.a); }
        var result = Value { .. };
        if value.tag == blot_check_core::Tag.array_op { result = arrayOp(self_, m, n.b, true); } else { result = visit(self_, m, n.b); }
        let fact = taken(self_, m, n.b, result);
        define(self_, n.a, fact);
        return Value { exits: result.exits, .. };
    }
    if tag == blot_check_core::Tag.update { return update(self_, m, id, 0); }
    if tag == blot_check_core::Tag.return_ {
        let leaves = self_.function_roots.len != 0 && n.b == self_.function_roots[self_.function_roots.len - 1];
        // A local that leaves with the function has no later use, so the
        // value keeps the local's fact; so does one a tail block breaks with.
        let tail = leaves && (n.b == self_.owned_result || self_.rules) && n.a != 0 && m.node(n.a).tag == blot_check_core::Tag.block_;
        if tail { self_.tails.push(n.a); }
        let logged = self_.reads.len;
        let result = visit(self_, m, n.a);
        if tail { self_.tails.resize(self_.tails.len - 1); }
        // Nothing runs after a return: its reads are the last on its path.
        if leaves && self_.dry { lastReads(self_, logged); }
        var fact: Fact = none;
        let ends = leaves || (self_.tails.len != 0 && self_.tails[self_.tails.len - 1] == n.b);
        if result.origin != 0 && ends && !self_.dry && m.node(n.a).tag == blot_check_core::Tag.reference && self_.home[result.origin] == self_.function_roots[self_.function_roots.len - 1] {
            fact = self_.facts[result.origin];
            kill(self_, result.origin);
        } else {
            fact = taken(self_, m, n.a, result);
        }
        if leaves && n.a != 0 && !result.exits && resultChecked(self_, m, n.b, m.typeOf(n.a)) && !ownedAs(self_, m, fact, m.typeOf(n.a), 0) { reject(self_, m, n.a, blot_check_core::Code.result_not_owned); }
        if leaves { return Value { exits: true, .. }; }
        var at = self_.blocks.len;
        while at != 0 {
            at -= 1;
            if self_.blocks[at].id != n.b { continue; }
            let met = meet(self_, self_.blocks[at].fact, fact);
            self_.blocks[at].fact = met;
            self_.blocks[at].broken = true;
            break;
        }
        return Value { .. };
    }
    if tag == blot_check_core::Tag.if_value || tag == blot_check_core::Tag.if_stmt { return conditional(self_, m, id); }
    if tag == blot_check_core::Tag.match_ { return match_(self_, m, id); }
    if tag == blot_check_core::Tag.pattern_bind {
        visitEscaping(self_, m, n.b);
        if n.c != 0 {
            let mark = self_.trail.len;
            let fallback = visit(self_, m, n.c);
            if fallback.exits { undo(self_, mark); }
        }
        return Value { .. };
    }
    if tag == blot_check_core::Tag.loop_ { return loop_(self_, m, id); }
    if tag == blot_check_core::Tag.break_ { return breakNode(self_, m, id); }
    if tag == blot_check_core::Tag.closure {
        // A spent capture is reported where the body reads it.
        for captured in m.closureCaptures(id) { read(self_, captured, id); kill(self_, captured); }
        let body = m.closure(id).body;
        let parameter = m.closure(id).parameter.binding;
        if local(self_, parameter) { self_.home[parameter] = body; }
        self_.function_roots.push(body);
        let logged = self_.reads.len;
        let value = visit(self_, m, body);
        // The closure's own locals end with its body. What it captured is
        // read again whenever it runs, so those reads are never the last.
        if self_.dry {
            lastReads(self_, logged);
            for captured in m.closureCaptures(id) { read(self_, captured, id); }
        }
        if self_.rules && !value.exits { ownedResult(self_, m, body, value); }
        escape(self_, value);
        self_.function_roots.resize(self_.function_roots.len - 1);
        return Value { .. };
    }
    if tag == blot_check_core::Tag.project {
        if taker(self_, m, id) != 0 { reject(self_, m, id, blot_check_core::Code.own_function_value); }
        let copied, is_copy = memberCopy(self_, m, id);
        if is_copy {
            // `values.copy` is the prelude's spelling of `@storage.copy`.
            let value = visit(self_, m, n.a);
            if elementHolds(self_, m, n.ty) { escape(self_, value); }
            return Value { fact: copied, exits: value.exits, .. };
        }
        if self_.rules && m.dispatchSignature(id) != 0 {
            let member = calleeBinding(self_, m, id);
            let lent = member != 0 && lentHere(self_, m, member, calleeType(m, id));
            if member != 0 && self_.reader_arity[member] <= 1 {
                // `value.member` with no further argument is the whole call.
                let value = visit(self_, m, n.a);
                if lent && owns(self_, m, n.ty) { return Value { origin: value.origin, exits: value.exits, .. }; }
                if lends(self_, m, n.ty) { escape(self_, value); }
                var fact: Fact = none;
                if owns(self_, m, n.ty) { fact = deep; }
                return Value { fact: fact, exits: value.exits, .. };
            }
            lentValue(self_, m, id);
        }
        let value = visit(self_, m, n.a);
        if !holds(self_, m, n.ty) { return Value { exits: value.exits, .. }; }
        return Value { origin: value.origin, exits: value.exits, .. };
    }
    if tag == blot_check_core::Tag.array {
        var elements_deep = true;
        var exits = false;
        for child in m.children(id) {
            let value = visit(self_, m, child);
            let fact = taken(self_, m, child, value);
            exits = exits || value.exits;
            elements_deep = elements_deep && fact == deep;
        }
        let fact = freshContainer(self_, m, n.ty, elements_deep);
        return Value { fact: fact, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.product && self_.rules {
        // A tuple nothing else holds: every part that can hold an array
        // is fresh or moved in.
        var parts_deep = true;
        var exits = false;
        for child in m.children(id) {
            let value = visit(self_, m, child);
            let fact = taken(self_, m, child, value);
            exits = exits || value.exits;
            parts_deep = parts_deep && (fact == deep || !holds(self_, m, m.typeOf(child)));
        }
        var fact: Fact = none;
        if parts_deep { fact = deep; }
        return Value { fact: fact, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.record { return recordLiteral(self_, m, id); }
    if tag == blot_check_core::Tag.construct {
        let payload = visit(self_, m, n.b);
        let literal = n.b != 0 && m.node(n.b).tag == blot_check_core::Tag.record;
        let held = taken(self_, m, n.b, payload);
        var fact: Fact = none;
        if literal && payload.origin == 0 { fact = held; }
        // A constructor holds what its payload does: nothing without one,
        // and a payload nothing else holds stays that way inside it.
        if self_.rules && (n.b == 0 || held == deep || !holds(self_, m, m.typeOf(n.b))) { fact = deep; }
        return Value { fact: fact, exits: payload.exits, .. };
    }
    if tag == blot_check_core::Tag.array_op { return arrayOp(self_, m, id, false); }
    if tag == blot_check_core::Tag.storage { return storageOp(self_, m, id); }
    if tag == blot_check_core::Tag.call && m.call(id).own != 0 {
        let exits = ownArguments(self_, m, m.call(id).arguments, m.call(id).own);
        // Every return of the callee gave a value nothing else holds.
        return Value { fact: deep, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.apply && self_.takers.count != 0 {
        // `f a b` and `a.f b` reach a function through its value: a
        // chain of applications, one argument each.
        var arguments: u32[32] = [0; 32];
        var count: i64 = 0;
        var callee = id;
        while count < 32 && m.node(callee).tag == blot_check_core::Tag.apply {
            arguments[count] = m.node(callee).b;
            count += 1;
            callee = m.node(callee).a;
        }
        let taking = taker(self_, m, callee);
        // The value of `value.member` is the first argument.
        if taking != 0 && count < 32 && m.node(callee).tag == blot_check_core::Tag.project {
            arguments[count] = m.node(callee).a;
            count += 1;
        }
        if taking != 0 && count == (taking >> 32) as i64 {
            for at in 0..count / 2 {
                let other = arguments[count - 1 - at];
                arguments[count - 1 - at] = arguments[at];
                arguments[at] = other;
            }
            let exits = ownArguments(self_, m, arguments[..count], taking as! u32);
            return Value { fact: deep, exits: exits, .. };
        }
    }
    if self_.rules && (tag == blot_check_core::Tag.call || tag == blot_check_core::Tag.apply) {
        // A call only borrows its arguments, and the arrays its result
        // owns are the caller's alone. A part of the result that borrows
        // (a view, a function) may hold the arguments, so then they are
        // shared from here on.
        var head = id;
        var count: i64 = 0;
        while m.node(head).tag == blot_check_core::Tag.apply { head = m.node(head).a; count += 1; }
        var binding: u32 = 0;
        var used_at: u32 = 0;
        if tag == blot_check_core::Tag.call {
            let target = m.call(id).target;
            let found .= self_.binding_index.get(((target.unit as u64) << 32) | target.binding);
            if found { let index: u32 = found; binding = index; }
            count = m.call(id).arguments.len;
            used_at = m.call(id).callee_type;
        } else {
            binding = calleeBinding(self_, m, head);
            if binding != 0 && m.node(head).tag == blot_check_core::Tag.project { count += 1; }
            used_at = calleeType(m, head);
        }
        // A generic function that returns what it was lent, called in
        // full where that holds an array: the result shares the arguments,
        // as `grid[0]` shares `grid`.
        if binding != 0 && reader(self_, m, binding) && count >= self_.reader_arity[binding] as i64 && owns(self_, m, n.ty) && lentHere(self_, m, binding, used_at) {
            var shared = Value { .. };
            if tag == blot_check_core::Tag.call {
                for child in m.call(id).arguments { let value = visit(self_, m, child); sharedWith(self_, shared, value); }
            } else {
                // The applications run outermost first here; which argument
                // the result is taken to alias does not matter.
                var cursor = id;
                while m.node(cursor).tag == blot_check_core::Tag.apply {
                    let value = visit(self_, m, m.node(cursor).b);
                    sharedWith(self_, shared, value);
                    cursor = m.node(cursor).a;
                }
                if m.node(head).tag == blot_check_core::Tag.project { let value = visit(self_, m, m.node(head).a); sharedWith(self_, shared, value); }
            }
            return shared;
        }
        // Whether the callee is a function value whose result is the
        // caller's: a named function, a closure, a function a call or a
        // field gave, a member this module can name. A constructor keeps
        // its argument, an effect operation's handler may keep it and
        // resume with a value it still holds, and a member reached through
        // a contract may be generic.
        let head_tag = m.node(head).tag;
        var known = tag == blot_check_core::Tag.call || head_tag == blot_check_core::Tag.reference || head_tag == blot_check_core::Tag.closure || head_tag == blot_check_core::Tag.call || head_tag == blot_check_core::Tag.if_value || head_tag == blot_check_core::Tag.match_ || head_tag == blot_check_core::Tag.block_;
        if head_tag == blot_check_core::Tag.project { known = binding != 0 || m.dispatchSignature(head) == 0; }
        if known {
            let holder = lends(self_, m, n.ty);
            var exits = false;
            if tag == blot_check_core::Tag.call {
                for child in m.call(id).arguments {
                    let value = visit(self_, m, child);
                    if holder { escape(self_, value); }
                    exits = exits || value.exits;
                }
            } else {
                let callee = visit(self_, m, n.a);
                let argument = visit(self_, m, n.b);
                if holder { escape(self_, callee); escape(self_, argument); }
                exits = callee.exits || argument.exits;
            }
            var fact: Fact = none;
            if owns(self_, m, n.ty) { fact = deep; }
            return Value { fact: fact, exits: exits, .. };
        }
    }
    if tag == blot_check_core::Tag.request_loop {
        // A handler loop carries locals the way a loop does, but through
        // its callbacks: each version it names is read by it and shared.
        for carry in m.requestLoopCarries(id) { read(self_, carry.incoming, id); kill(self_, carry.incoming); }
        let exits = visitChildren(self_, m, id);
        for carry in m.requestLoopCarries(id) {
            read(self_, carry.iteration, id);
            read(self_, carry.backedge, id);
            read(self_, carry.outgoing, id);
            kill(self_, carry.backedge);
        }
        for binding in m.requestCompletionBindings(id) { read(self_, binding, id); }
        return Value { exits: exits, .. };
    }
    let exits = visitChildren(self_, m, id);
    return Value { exits: exits, .. };
}

// The identity the backend's dispatch gives a receiver of type `ty`.
fn receiverIdentity(m: const Module&, ty: u32) -> blot_check_types::NominalIdentity, bool {
    var identity = blot_check_types::NominalIdentity { unit: 0, decl: ty };
    if ty == 0 || ty >= m.types.nodes.len { return identity, false; }
    let shape = m.types.node(ty);
    if shape.tag == blot_check_types::Tag.nominal {
        identity = blot_check_types::NominalIdentity { unit: shape.a, decl: shape.b };
    } else if shape.tag == blot_check_types::Tag.array {
        identity.decl = 0xffffffff;
    } else if shape.tag == blot_check_types::Tag.unsigned32 {
        identity.decl = blot_check_types::u32_type;
    } else if shape.tag == blot_check_types::Tag.floating32 {
        identity.decl = blot_check_types::f32_type;
    } else if shape.tag == blot_check_types::Tag.boolean {
        identity.decl = blot_check_types::boolean;
    } else if shape.tag == blot_check_types::Tag.unit {
        identity.decl = blot_check_types::unit;
    } else {
        return identity, false;
    }
    return identity, true;
}
// The binding a reference names, or the member `value.member` selects; 0
// when this module's tables do not say.
fn calleeBinding(self_: const Analyzer&, m: const Module&, node: u32) -> u32 {
    let n = m.node(node);
    if n.tag == blot_check_core::Tag.reference {
        let target = m.reference(node);
        let found .= self_.binding_index.get(((target.unit as u64) << 32) | target.binding);
        if !found { return 0; }
        let index: u32 = found;
        return index;
    }
    if n.tag != blot_check_core::Tag.project || m.dispatchSignature(node) == 0 { return 0; }
    let identity, known = receiverIdentity(m, m.typeOf(n.a));
    if !known { return 0; }
    let id .= self_.identity_ids.get(((identity.unit as u64) << 32) | identity.decl);
    if !id { return 0; }
    let identity_id: u32 = id;
    let found .= self_.members.get(((identity_id as u64) << 32) | m.projection(n.b).field);
    if !found { return 0; }
    let index: u32 = found;
    return index;
}
// Whether `variable` occurs in `ty`; with `data`, not counting what is
// under a function type. A shape this cannot read counts as holding it.
recursive fn occurs(m: const Module&, variable: u32, ty: u32, data: bool, depth: i64) -> bool {
    if ty == variable { return true; }
    if ty == 0 || ty >= m.types.nodes.len { return false; }
    if depth > 64 { return true; }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.absent || n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return false; }
    if n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound { return false; }
    if n.tag == blot_check_types::Tag.function {
        if data { return false; }
        return occurs(m, variable, n.a, data, depth + 1) || occurs(m, variable, n.b, data, depth + 1);
    }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor { return occurs(m, variable, n.a, data, depth + 1); }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) { if occurs(m, variable, item, data, depth + 1) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b { if occurs(m, variable, m.types.recordField(n, index).ty, data, depth + 1) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.nominal {
        for argument in m.types.nominalArguments(n) { if occurs(m, variable, argument, data, depth + 1) { return true; } }
        return false;
    }
    return true;
}
// Whether `binding` is a generic function that may return what it was lent:
// a type variable of its scheme occurs in its result and, as data, in a
// parameter it does not take over. Also sets how many arguments its type
// takes. Inside its body the variable is plain data, so nothing there
// stops it returning the parameter; each call decides (rule 2).
fn reader(self_: Analyzer&, m: const Module&, binding: u32) -> bool {
    if binding == 0 || binding >= self_.reader_state.len { return false; }
    if self_.reader_state[binding] != 0 { return self_.reader_state[binding] == 2; }
    self_.reader_state[binding] = 1;
    let scheme = m.bindings[binding].scheme;
    if scheme.root == 0 || scheme.root >= m.types.nodes.len { return false; }
    let own = m.bindings[binding].capability_parameters.own;
    var result = scheme.root;
    var arity: u32 = 0;
    while arity < 255 && m.types.node(result).tag == blot_check_types::Tag.function { result = m.types.node(result).b; arity += 1; }
    self_.reader_arity[binding] = arity as! u8;
    let variables = m.types.list(scheme.variables);
    var found = false;
    for variable in variables {
        if !occurs(m, variable, result, false, 0) { continue; }
        var parameter = scheme.root;
        for position in 0..(arity as i64) {
            let taken_over = position < 32 && (own >> (position as! u32)) & 1 != 0;
            if !taken_over && occurs(m, variable, m.types.node(parameter).a, true, 0) { found = true; }
            parameter = m.types.node(parameter).b;
        }
    }
    if found { self_.reader_state[binding] = 2; }
    return found;
}
// Adds `argument` to what the result `shared` of a call may alias. A value
// names one version, so the first argument that is one stands for the
// result and every other one is shared outright.
fn sharedWith(self_: Analyzer&, shared: Value&, argument: Value) {
    shared.exits = shared.exits || argument.exits;
    if shared.origin == 0 && argument.origin != 0 { shared.origin = argument.origin; return; }
    escape(self_, argument);
}
// Whether `actual`, an instance of the scheme type `pattern`, gives
// `variable` a type that owns an array. Where the two cannot be matched it
// may.
recursive fn instanceOwns(self_: Analyzer&, m: const Module&, pattern: u32, actual: u32, variable: u32, depth: i64) -> bool {
    if pattern == variable { return owns(self_, m, actual); }
    if !occurs(m, variable, pattern, false, 0) { return false; }
    if depth > 64 || actual == 0 || actual >= m.types.nodes.len || pattern >= m.types.nodes.len { return true; }
    let p = m.types.node(pattern);
    let a = m.types.node(actual);
    if p.tag != a.tag { return true; }
    if p.tag == blot_check_types::Tag.function { return instanceOwns(self_, m, p.a, a.a, variable, depth + 1) || instanceOwns(self_, m, p.b, a.b, variable, depth + 1); }
    if p.tag == blot_check_types::Tag.array || p.tag == blot_check_types::Tag.list || p.tag == blot_check_types::Tag.cursor { return instanceOwns(self_, m, p.a, a.a, variable, depth + 1); }
    if p.tag == blot_check_types::Tag.product {
        if p.b != a.b { return true; }
        let left = m.types.list(blot_check_types::List { start: p.a, len: p.b });
        let right = m.types.list(blot_check_types::List { start: a.a, len: a.b });
        for item, at in left { if instanceOwns(self_, m, item, right[at], variable, depth + 1) { return true; } }
        return false;
    }
    if p.tag == blot_check_types::Tag.record {
        if p.b != a.b { return true; }
        for index in 0..p.b { if instanceOwns(self_, m, m.types.recordField(p, index).ty, m.types.recordField(a, index).ty, variable, depth + 1) { return true; } }
        return false;
    }
    if p.tag == blot_check_types::Tag.nominal {
        let left = m.types.nominalArguments(p);
        let right = m.types.nominalArguments(a);
        if p.a != a.a || p.b != a.b || left.len != right.len { return true; }
        for item, at in left { if instanceOwns(self_, m, item, right[at], variable, depth + 1) { return true; } }
        return false;
    }
    return true;
}
// Whether this use of the generic function `binding`, at the function type
// `actual`, may get back an array it lent: one of the type variables that
// make it a reader stands for a type that owns an array here.
fn lentHere(self_: Analyzer&, m: const Module&, binding: u32, actual: u32) -> bool {
    if !reader(self_, m, binding) { return false; }
    let scheme = m.bindings[binding].scheme;
    let own = m.bindings[binding].capability_parameters.own;
    let arity = self_.reader_arity[binding] as i64;
    var result = scheme.root;
    for position in 0..arity { result = m.types.node(result).b; }
    for variable in m.types.list(scheme.variables) {
        if !occurs(m, variable, result, false, 0) { continue; }
        var lent = false;
        var parameter = scheme.root;
        for position in 0..arity {
            let taken_over = position < 32 && (own >> (position as! u32)) & 1 != 0;
            if !taken_over && occurs(m, variable, m.types.node(parameter).a, true, 0) { lent = true; }
            parameter = m.types.node(parameter).b;
        }
        if lent && instanceOwns(self_, m, scheme.root, actual, variable, 0) { return true; }
    }
    return false;
}
// The function type a callee is used at: a reference's own type, or for
// `value.member` the member's type with the value as its first parameter.
fn calleeType(m: const Module&, node: u32) -> u32 {
    if m.node(node).tag == blot_check_core::Tag.project { return m.dispatchSignature(node); }
    return m.typeOf(node);
}
// A reference to, or a member projection of, a generic function that
// returns what it was lent, where that holds an array and the function is
// not being called in full: its value would be a function whose result is
// not the caller's alone.
fn lentValue(self_: Analyzer&, m: const Module&, node: u32) {
    if !self_.rules { return; }
    let binding = calleeBinding(self_, m, node);
    if binding == 0 { return; }
    if lentHere(self_, m, binding, calleeType(m, node)) { reject(self_, m, node, blot_check_core::Code.lent_result_value); }
}
// The own mask and argument count of the function `node` names, or 0.
fn taker(self_: const Analyzer&, m: const Module&, node: u32) -> u64 {
    if self_.takers.count == 0 { return 0; }
    if m.node(node).tag == blot_check_core::Tag.project {
        // `value.member`: the member is a function of the value's type.
        let field = m.projection(m.node(node).b).field;
        let identity, known = receiverIdentity(m, m.typeOf(m.node(node).a));
        if !known { return 0; }
        for method in self_.member_takers {
            if method.member == field && method.identity.unit == identity.unit && method.identity.decl == identity.decl { return method.taking; }
        }
        return 0;
    }
    if m.node(node).tag != blot_check_core::Tag.reference { return 0; }
    let target = m.reference(node);
    let found .= self_.takers.get(((target.unit as u64) << 32) | target.binding);
    if !found { return 0; }
    let value: u64 = found;
    return value;
}
// The arguments of a full call of a function that takes over the parameters
// in `mask`. An `own` argument must be a fresh value, or a local that holds
// its value alone; the local is spent. Inside a loop the local must belong
// to the same iteration, or the next one would give it away again.
recursive fn ownArguments(self_: Analyzer&, m: const Module&, arguments: const u32[:], mask: u32) -> bool {
    var exits = false;
    for child, position in arguments {
        var named: u32 = 0;
        if m.node(child).tag == blot_check_core::Tag.reference {
            let target = m.reference(child);
            if (target.unit == 0 || target.unit == m.unit) && local(self_, target.binding) { named = target.binding; }
        }
        let was_spent = named != 0 && self_.facts[named] == spent;
        let value = visit(self_, m, child);
        exits = exits || value.exits;
        let ty = m.typeOf(child);
        if position >= 32 || (mask >> (position as! u32)) & 1 == 0 || !holds(self_, m, ty) { escape(self_, value); continue; }
        if was_spent { continue; }
        var accepted = false;
        if value.origin == 0 {
            accepted = ownedAs(self_, m, value.fact, ty, 0);
        } else if named != 0 {
            var loop_id: u32 = 0;
            if self_.loops.len != 0 { loop_id = self_.loops[self_.loops.len - 1].id; }
            accepted = self_.born[named] == loop_id && ownedAs(self_, m, self_.facts[named], ty, 0);
        }
        if !accepted { reject(self_, m, child, blot_check_core::Code.own_argument); }
        if accepted && named != 0 { set(self_, named, spent); } else { escape(self_, value); }
    }
    return exits;
}
// The value a function with an `own` parameter ends with, when it ends
// without a `return`.
fn ownedResult(self_: Analyzer&, m: const Module&, node: u32, value: Value) {
    var fact = value.fact;
    if value.origin != 0 {
        fact = none;
        if m.node(node).tag == blot_check_core::Tag.reference { fact = self_.facts[value.origin]; }
    }
    if self_.rules && !owns(self_, m, m.typeOf(node)) { return; }
    if !ownedAs(self_, m, fact, m.typeOf(node), 0) { reject(self_, m, node, blot_check_core::Code.result_not_owned); }
}
// Whether the function or closure with `root` must return a value nothing
// else holds: one that takes over a parameter, and under the rules being
// measured every one whose result can own an array.
fn resultChecked(self_: Analyzer&, m: const Module&, root: u32, ty: u32) -> bool {
    if self_.rules { return owns(self_, m, ty); }
    return root == self_.owned_result;
}
// Whether a value of `ty` with `fact` is unique all the way down. A record
// fact is when every field that holds storage is; a nominal is read through
// its one record constructor when it has no type parameters.
recursive fn ownedAs(self_: Analyzer&, m: const Module&, fact: Fact, ty: u32, depth: i64) -> bool {
    if fact == deep { return true; }
    if !holds(self_, m, ty) { return true; }
    // A part that only borrows may hold what it likes.
    if self_.rules && !owns(self_, m, ty) { return true; }
    if fact < first_record || fact >= spent || depth > 16 || ty >= m.types.nodes.len { return false; }
    var shape = m.types.node(ty);
    if shape.tag == blot_check_types::Tag.nominal {
        if blot_check_storage_types::identity(shape.a, shape.b).present || shape.a == 0xffffffff { return false; }
        let index, found = nominalIndex(self_, m, shape.a, shape.b);
        if !found { return false; }
        let nominal = m.nominal(index);
        let constructors = m.nominalConstructors(index);
        if nominal.is_opaque || nominal.variables.len != 0 || constructors.len != 1 { return false; }
        let payload = m.constructor(constructors[0]).payload;
        if payload == 0 || payload >= m.types.nodes.len { return false; }
        shape = m.types.node(payload);
    }
    if shape.tag != blot_check_types::Tag.record { return false; }
    for index in 0..shape.b {
        let declared = m.types.recordField(shape, index);
        if !ownedAs(self_, m, field(self_, fact, declared.name), declared.ty, depth + 1) { return false; }
    }
    return true;
}

// The fresh fact of `values.copy` on an array, which only the prelude can
// define; false for every other projection.
fn memberCopy(self_: Analyzer&, m: const Module&, id: u32) -> Fact, bool {
    let n = m.node(id);
    let spelling = m.fieldSpelling(m.projection(n.b).field);
    if !spelling.present || spelling.value != "copy" { return none, false; }
    if !blot_check_storage_types::arrayElement(m.types, m.typeOf(n.a)).present || !blot_check_storage_types::arrayElement(m.types, n.ty).present { return none, false; }
    return freshContainer(self_, m, n.ty, false), true;
}
recursive fn block_(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    self_.blocks.push(BlockFrame { id: id, .. });
    var exits = false;
    for child in m.children(id) { let value = visit(self_, m, child); exits = value.exits || exits; }
    let frame = self_.blocks[self_.blocks.len - 1];
    self_.blocks.resize(self_.blocks.len - 1);
    if frame.broken {
        var fact = frame.fact;
        if fact == top { fact = none; }
        return Value { fact: fact, .. };
    }
    return Value { exits: exits, .. };
}

recursive fn recordLiteral(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let n = m.node(id);
    var shape = blot_check_types::Node { tag: blot_check_types::Tag.absent, .. };
    if n.ty != 0 && n.ty < m.types.nodes.len { shape = m.types.node(n.ty); }
    let is_record = shape.tag == blot_check_types::Tag.record;
    let mark = self_.scratch.len;
    var exits = false;
    for child, index in m.children(id) {
        let value = visit(self_, m, child);
        let fact = taken(self_, m, child, value);
        exits = exits || value.exits;
        if !is_record { continue; }
        let destination = m.recordDestinations(id)[index];
        if destination >= shape.b { continue; }
        let declared = m.types.recordField(shape, destination);
        if !holds(self_, m, declared.ty) { continue; }
        pushSorted(self_, mark, Entry { field: declared.name, fact: fact });
    }
    if !is_record { return Value { exits: exits, .. }; }
    let fact = makeRecord(self_, none, mark);
    self_.scratch.resize(mark);
    return Value { fact: fact, exits: exits, .. };
}

// A `:=` path update bound to `successor`, or a store when the update is
// flagged as one (then `successor` is zero).
recursive fn update(self_: Analyzer&, m: const Module&, id: u32, successor: u32) -> Value {
    let info = m.updateInfo(id);
    let selectors = m.updateSelectors(id);
    let root = visit(self_, m, info.root);
    for step in selectors { if step.kind == blot_check_core::UpdateKind.index { visitEscaping(self_, m, step.index); } }
    let value = visit(self_, m, info.value);
    let replacement = taken(self_, m, info.value, value);
    var through_storage = false;
    for step in selectors { through_storage = through_storage || step.kind == blot_check_core::UpdateKind.index; }
    var leaf = m.typeOf(info.value);
    if selectors.len != 0 { leaf = selectors[selectors.len - 1].result_type; }
    let shared = holds(self_, m, leaf) && replacement != deep;
    if info.store {
        if shared { sharedInto(self_, m, info.root, selectors); }
        return Value { .. };
    }
    var old: Fact = none;
    if local(self_, root.origin) { old = self_.facts[root.origin]; }
    let mark = self_.fields.len;
    if !through_storage {
        // A value path rebuilds records; the replaced field takes the
        // value's fact and every other field keeps its storage.
        if selectors.len != 0 {
            for step in selectors { self_.fields.push(m.projection(step.projection).field); }
        } else {
            for projection in m.updatePath(id) { self_.fields.push(m.projection(projection).field); }
        }
        let replaced = replace(self_, old, self_.fields[mark..], replacement);
        self_.fields.resize(mark);
        define(self_, successor, replaced);
        return Value { exits: value.exits, .. };
    }
    if !accepts(self_, m, old, selectors) { reject(self_, m, id, blot_check_core::Code.aliased_update); }
    for step in selectors {
        if step.kind == blot_check_core::UpdateKind.index { break; }
        self_.fields.push(m.projection(step.projection).field);
    }
    var next = old;
    if shared { next = weaken(self_, old, self_.fields[mark..]); }
    self_.fields.resize(mark);
    define(self_, successor, next);
    return Value { exits: value.exits, .. };
}
recursive fn replace(self_: Analyzer&, fact: Fact, fields: const u32[:], replacement: Fact) -> Fact {
    if fields.len == 0 { return replacement; }
    let inner = replace(self_, field(self_, fact, fields[0]), fields[1..], replacement);
    return withField(self_, fact, fields[0], inner);
}
// Every storage the path writes through must be unique.
fn accepts(self_: const Analyzer&, m: const Module&, fact: Fact, selectors: const UpdateStep[:]) -> bool {
    var current = fact;
    for step in selectors {
        if step.kind == blot_check_core::UpdateKind.field {
            current = field(self_, current, m.projection(step.projection).field);
        } else {
            if !unique(current) { return false; }
            if current != deep { current = none; }
        }
    }
    return true;
}

// `bound`: the operation is a binding's whole value, where the backend
// appends in place to an input named once.
recursive fn arrayOp(self_: Analyzer&, m: const Module&, id: u32, bound: bool) -> Value {
    let n = m.node(id);
    let children = m.children(id);
    let operation = m.arrayOperation(id);
    if operation == blot_backend_collection_ops::Op.length {
        let container = visit(self_, m, children[0]);
        return Value { exits: container.exits, .. };
    }
    if operation == blot_backend_collection_ops::Op.get || operation == blot_backend_collection_ops::Op.simd_load {
        let container = visit(self_, m, children[0]);
        let index = visitEscaping(self_, m, children[1]);
        let exits = container.exits || index.exits;
        if operation == blot_backend_collection_ops::Op.get && holds(self_, m, n.ty) { return Value { origin: container.origin, exits: exits, .. }; }
        return Value { exits: exits, .. };
    }
    if operation == blot_backend_collection_ops::Op.identity { return visit(self_, m, children[0]); }
    if operation == blot_backend_collection_ops::Op.simd_store {
        // Writes four elements in place and returns the same storage.
        let container = visit(self_, m, children[0]);
        for child in children[1..] { visitEscaping(self_, m, child); }
        return Value { origin: container.origin, exits: container.exits, .. };
    }
    if operation == blot_backend_collection_ops::Op.set || operation == blot_backend_collection_ops::Op.concat || operation == blot_backend_collection_ops::Op.slice || operation == blot_backend_collection_ops::Op.flatten || operation == blot_backend_collection_ops::Op.convert || operation == blot_backend_collection_ops::Op.prepend || operation == blot_backend_collection_ops::Op.append {
        // A new container whose elements are copies of the inputs'.
        let shares = elementHolds(self_, m, n.ty);
        var exits = false;
        var inputs_unique = true;
        for child, position in children {
            let container_input = position == 0 || operation == blot_backend_collection_ops::Op.concat;
            let value = visit(self_, m, child);
            exits = exits || value.exits;
            if !container_input || shares { escape(self_, value); }
            // A bound append to a reference used once grows that input in
            // place, so the result shares its storage.
            if bound && operation == blot_backend_collection_ops::Op.append && position == 0 && m.node(child).tag == blot_check_core::Tag.reference {
                inputs_unique = local(self_, value.origin) && unique(self_.facts[value.origin]);
            }
        }
        if !inputs_unique { return Value { exits: exits, .. }; }
        let fact = freshContainer(self_, m, n.ty, false);
        return Value { fact: fact, exits: exits, .. };
    }
    if operation == blot_backend_collection_ops::Op.fill || operation == blot_backend_collection_ops::Op.generate {
        var exits = false;
        for child in children { let value = visitEscaping(self_, m, child); exits = value.exits || exits; }
        let fact = freshContainer(self_, m, n.ty, false);
        return Value { fact: fact, exits: exits, .. };
    }
    // cursor, cursor_has, cursor_value, cursor_advance
    let exits = visitChildren(self_, m, id);
    return Value { exits: exits, .. };
}

recursive fn storageOp(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let n = m.node(id);
    let children = m.children(id);
    let operation, unknown = blot_check_storage_ops::opFromCode(n.c);
    if unknown == blot_error::Error.none {
        if operation == blot_check_storage_ops::Op.length || operation == blot_check_storage_ops::Op.truncate || operation == blot_check_storage_ops::Op.reserve || operation == blot_check_storage_ops::Op.pop {
            let container = visit(self_, m, children[0]);
            var exits = container.exits;
            for child in children[1..] { let value = visitEscaping(self_, m, child); exits = value.exits || exits; }
            return Value { exits: exits, .. };
        }
        if operation == blot_check_storage_ops::Op.read {
            let container = visit(self_, m, children[0]);
            let index = visitEscaping(self_, m, children[1]);
            let exits = container.exits || index.exits;
            if holds(self_, m, n.ty) { return Value { origin: container.origin, exits: exits, .. }; }
            return Value { exits: exits, .. };
        }
        if operation == blot_check_storage_ops::Op.push {
            let container = visit(self_, m, children[0]);
            let value = visit(self_, m, children[1]);
            var pushed = value.fact;
            if self_.rules { pushed = taken(self_, m, children[1], value); } else { escape(self_, value); if value.origin != 0 { pushed = none; } }
            if elementHolds(self_, m, m.typeOf(children[0])) && pushed != deep { sharedInto(self_, m, children[0], []); }
            return Value { exits: container.exits || value.exits, .. };
        }
        if operation == blot_check_storage_ops::Op.copy {
            let container = visit(self_, m, children[0]);
            if elementHolds(self_, m, n.ty) { escape(self_, container); }
            let fact = freshContainer(self_, m, n.ty, false);
            return Value { fact: fact, exits: container.exits, .. };
        }
        if operation == blot_check_storage_ops::Op.freeze {
            let container = visit(self_, m, children[0]);
            // Freezing a local at its last read gives its storage away.
            if self_.rules && container.origin != 0 && moves(self_, m, children[0], container.origin) {
                let fact = self_.facts[container.origin];
                kill(self_, container.origin);
                return Value { fact: fact, exits: container.exits, .. };
            }
            return Value { origin: container.origin, exits: container.exits, .. };
        }
    }
    // References, views and links alias the storage they name.
    let exits = visitChildren(self_, m, id);
    return Value { exits: exits, .. };
}

recursive fn conditional(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let n = m.node(id);
    let condition = visitEscaping(self_, m, n.a);
    var join = joinInit(self_, m.branchMerges(id));
    let first = visit(self_, m, n.b);
    arm(self_, join, 0, first);
    var second = Value { .. };
    if n.c != 0 { second = visit(self_, m, n.c); }
    arm(self_, join, 1, second);
    let value = finish(self_, join);
    var fact: Fact = none;
    if n.tag == blot_check_core::Tag.if_value { fact = value.fact; }
    return Value { fact: fact, exits: condition.exits || value.exits, .. };
}

recursive fn match_(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let info = m.matchInfo(id);
    var exits = false;
    for input in m.matchInputs(id) { let value = visitEscaping(self_, m, input); exits = value.exits || exits; }
    var join = joinInit(self_, m.branchMerges(id));
    for case_, index in m.matchArms(id) {
        var guard_exits = false;
        if case_.guard_ != 0 { let guarded = visitEscaping(self_, m, case_.guard_); guard_exits = guarded.exits; }
        var body = Value { .. };
        if case_.body != 0 { body = visit(self_, m, case_.body); }
        body.exits = body.exits || guard_exits;
        arm(self_, join, index, body);
    }
    let value = finish(self_, join);
    var fact = value.fact;
    if info.statement { fact = none; }
    return Value { fact: fact, exits: exits || value.exits, .. };
}

recursive fn loop_(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let info = m.loopInfo(id);
    let carries = m.loopCarries(id);
    var exits = false;
    var iterated: u32 = 0;
    if info.kind == blot_check_core::LoopKind.range {
        let first = visitEscaping(self_, m, info.first);
        exits = first.exits || exits;
        let end = visitEscaping(self_, m, info.end);
        exits = end.exits || exits;
    } else if info.kind == blot_check_core::LoopKind.array {
        // The pattern binds elements, so storage-holding ones alias. The
        // loop reads its source throughout, so a carry that starts as the
        // source is observed by every iteration.
        let source = visit(self_, m, info.first);
        exits = source.exits;
        if elementHolds(self_, m, m.typeOf(info.first)) { escape(self_, source); } else { iterated = source.origin; }
    }
    // The carries' facts are four runs of `count` on `loop_facts`:
    // incoming, assumed, result and outgoing.
    let count = carries.len;
    let incoming = self_.loop_facts.len;
    let assumed = incoming + count;
    let result = assumed + count;
    let outgoing = result + count;
    for carry in carries {
        var fact: Fact = none;
        read(self_, carry.incoming, id);
        if local(self_, carry.incoming) && carry.incoming != iterated { fact = self_.facts[carry.incoming]; }
        self_.loop_facts.push(fact);
    }
    for at in 0..count { let fact = self_.loop_facts[incoming + at]; self_.loop_facts.push(fact); }
    for at in 0..count * 2 { self_.loop_facts.push(none); }
    if self_.probing != 0 {
        // Inside a probe: one optimistic pass approximates the carries.
        loopPass(self_, m, id, carries, assumed);
    } else {
        self_.probing += 1;
        let mark = self_.trail.len;
        loopPass(self_, m, id, carries, assumed);
        undo(self_, mark);
        self_.probing -= 1;
        for at in 0..count {
            let met = meet(self_, self_.loop_facts[incoming + at], self_.loop_facts[result + at]);
            self_.loop_facts[assumed + at] = met;
        }
        var attempt: i64 = 0;
        loop {
            let checked = self_.trail.len;
            let rejected = self_.rejections.len;
            loopPass(self_, m, id, carries, assumed);
            var stable = true;
            for at in 0..count {
                let fact = self_.loop_facts[assumed + at];
                let reached = meet(self_, self_.loop_facts[incoming + at], self_.loop_facts[result + at]);
                let next = meet(self_, fact, reached);
                if !same(self_, next, fact) { stable = false; }
                var stored = next;
                if attempt >= 2 && stored != spent { stored = none; }
                self_.loop_facts[assumed + at] = stored;
            }
            if stable { break; }
            // A probe that underestimated the carries: check again.
            undo(self_, checked);
            self_.rejections.resize(rejected);
            attempt += 1;
        }
    }
    for carry, at in carries {
        let met = meet(self_, self_.loop_facts[assumed + at], self_.loop_facts[outgoing + at]);
        define(self_, carry.outgoing, met);
    }
    self_.loop_facts.resize(incoming);
    return Value { exits: exits || (info.kind == blot_check_core::LoopKind.forever && !info.can_exit), .. };
}
// One pass over a loop body with its carries at `loop_facts[assumed..]`. The
// run after it receives the facts reaching the next iteration, and the run
// after that those carried out by breaks.
recursive fn loopPass(self_: Analyzer&, m: const Module&, id: u32, carries: const LoopCarry[:], assumed: i64) {
    let info = m.loopInfo(id);
    let count = carries.len;
    let start = self_.carried.len;
    for at in 0..count * 2 { self_.carried.push(top); }
    self_.loops.push(LoopFrame { id: id, start: start, len: count });
    // Defined inside the frame: each iteration has its own version.
    for carry, at in carries { define(self_, carry.iteration, self_.loop_facts[assumed + at]); }
    let body = visit(self_, m, info.body);
    self_.loops.resize(self_.loops.len - 1);
    for carry, at in carries {
        var backedge: Fact = none;
        read(self_, carry.backedge, id);
        if body.exits { backedge = top; } else if local(self_, carry.backedge) { backedge = self_.facts[carry.backedge]; }
        let next = meet(self_, backedge, self_.carried[start + at]);
        self_.loop_facts[assumed + count + at] = next;
        self_.loop_facts[assumed + count * 2 + at] = self_.carried[start + count + at];
    }
    self_.carried.resize(start);
}
recursive fn breakNode(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let n = m.node(id);
    var found = false;
    var frame = LoopFrame { id: 0, start: 0, len: 0 };
    var at = self_.loops.len;
    while at != 0 {
        at -= 1;
        if self_.loops[at].id == n.a { frame = self_.loops[at]; found = true; break; }
    }
    for child, position in m.breakValues(id) {
        // A carried version moves to the loop's next iteration or exit; that
        // is not an alias.
        let value = visit(self_, m, child);
        var fact = value.fact;
        if m.node(child).tag == blot_check_core::Tag.reference && value.origin != 0 {
            fact = self_.facts[value.origin];
        } else {
            escape(self_, value);
            if value.origin != 0 { fact = none; }
        }
        if !found || position >= frame.len { continue; }
        var slot = frame.start + position;
        if n.op != blot_check_core::Op.continue_ { slot += frame.len; }
        let met = meet(self_, self_.carried[slot], fact);
        self_.carried[slot] = met;
    }
    return Value { .. };
}

// ---- Joins -------------------------------------------------------------

fn joinInit(self_: Analyzer&, merges: const Merge[:]) -> Join {
    let join = Join { log: self_.reads.len, base: self_.trail.len, merges: merges, changed_start: self_.changed.len, merged_start: self_.merged.len, .. };
    for at in 0..merges.len { self_.merged.push(top); }
    return join;
}
fn arm(self_: Analyzer&, join: Join&, index: i64, result: Value) {
    if self_.dry {
        // An arm that only leaves the function reads nothing afterwards.
        if result.exits { lastReads(self_, join.log); }
        if index < 2 {
            for merge in join.merges {
                var binding = merge.else_binding;
                if index == 0 { binding = merge.then_binding; }
                read(self_, binding, merge.node);
            }
        }
        join.log = self_.reads.len;
    }
    if !result.exits {
        escape(self_, result);
        join.exits = false;
        join.falls += 1;
        var fact = result.fact;
        if result.origin != 0 { fact = none; }
        join.value = meet(self_, join.value, fact);
        if index < 2 {
            for merge, at in join.merges {
                var binding = merge.else_binding;
                if index == 0 { binding = merge.then_binding; }
                var current: Fact = none;
                if local(self_, binding) { current = self_.facts[binding]; }
                let met = meet(self_, self_.merged[join.merged_start + at], current);
                self_.merged[join.merged_start + at] = met;
            }
        }
        var at = join.base;
        while at < self_.trail.len {
            let binding = self_.trail[at].binding;
            at += 1;
            let slot = self_.changed_slot[binding];
            if slot < join.changed_start {
                self_.changed.push(Changed { binding: binding, fact: self_.facts[binding], arms: 1, last: index, previous: slot });
                self_.changed_slot[binding] = self_.changed.len - 1;
            } else if self_.changed[slot].last != index {
                let met = meet(self_, self_.changed[slot].fact, self_.facts[binding]);
                self_.changed[slot].fact = met;
                self_.changed[slot].arms += 1;
                self_.changed[slot].last = index;
            }
        }
    }
    undo(self_, join.base);
}
fn finish(self_: Analyzer&, join: Join&) -> Value {
    var at = join.changed_start;
    while at < self_.changed.len {
        let entry = self_.changed[at];
        at += 1;
        var fact = entry.fact;
        // An arm that left this binding alone carries the base fact.
        if entry.arms < join.falls { fact = meet(self_, fact, self_.facts[entry.binding]); }
        set(self_, entry.binding, fact);
    }
    for merge, index in join.merges {
        var fact = self_.merged[join.merged_start + index];
        if fact == top { fact = none; }
        define(self_, merge.result, fact);
    }
    var release = self_.changed.len;
    while release > join.changed_start {
        release -= 1;
        self_.changed_slot[self_.changed[release].binding] = self_.changed[release].previous;
    }
    self_.changed.resize(join.changed_start);
    self_.merged.resize(join.merged_start);
    var value = join.value;
    if value == top { value = none; }
    return Value { fact: value, exits: join.exits, .. };
}
