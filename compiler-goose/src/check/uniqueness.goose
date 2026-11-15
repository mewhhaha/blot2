// Uniqueness of `:=` paths through storage (tasks/MEMORY_MODEL.md, rules 4
// and 5; compiler/src/check/uniqueness.zig). A path update that reaches
// storage writes in place, which is only the successor semantics of `:=` when
// nothing else can observe the old root. This pass proves that inside one
// body and rejects the rest with `aliased_update`; no fact crosses a call.
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
struct Rejection { node: u32, span: blot_check_core::Span }
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
    probing: u32 = 0
}

// Appends one `aliased_update` diagnostic per rejected `:=` in `module`.
fn check(module: const Module&, out: blot_check_core::Diagnostic[>..<]&) {
    if module.updates.len == 0 { return; }
    var analyzer = Analyzer { .. };
    for at in 0..module.bindings.len { analyzer.facts.push(none); analyzer.changed_slot.push(-1); }
    for body, index in module.bodies {
        if index == 0 || body.root == 0 { continue; }
        analyzer.function_roots.push(body.root);
        let value = visit(analyzer, module, body.root);
        escape(analyzer, value);
        analyzer.function_roots.resize(analyzer.function_roots.len - 1);
    }
    sort(analyzer.rejections[..]) { a, b => a.node < b.node }
    var previous: u32 = 0;
    for rejection in analyzer.rejections {
        if rejection.node == previous { continue; }
        previous = rejection.node;
        out.push(blot_check_core::Diagnostic { code: blot_check_core::Code.aliased_update, span: rejection.span });
    }
}

// ---- Facts -------------------------------------------------------------

fn local(self_: const Analyzer&, binding: u32) -> bool { return binding != 0 && binding < self_.facts.len; }
fn set(self_: Analyzer&, binding: u32, fact: Fact) {
    if !local(self_, binding) || self_.facts[binding] == fact { return; }
    self_.trail.push(Change { binding: binding, old: self_.facts[binding] });
    self_.facts[binding] = fact;
}
fn kill(self_: Analyzer&, binding: u32) { set(self_, binding, none); }
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
    if left < first_record || right < first_record || left == top || right == top { return false; }
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
        if target.unit != 0 && target.unit != m.unit { return Value { .. }; }
        if local(self_, target.binding) { return Value { origin: target.binding, .. }; }
        return Value { .. };
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
        escape(self_, result);
        var fact = result.fact;
        if result.origin != 0 { fact = none; }
        set(self_, n.a, fact);
        return Value { exits: result.exits, .. };
    }
    if tag == blot_check_core::Tag.update { return update(self_, m, id, 0); }
    if tag == blot_check_core::Tag.return_ {
        let result = visitEscaping(self_, m, n.a);
        var fact = result.fact;
        if result.origin != 0 { fact = none; }
        if self_.function_roots.len != 0 && n.b == self_.function_roots[self_.function_roots.len - 1] { return Value { exits: true, .. }; }
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
        for captured in m.closureCaptures(id) { kill(self_, captured); }
        let body = m.closure(id).body;
        self_.function_roots.push(body);
        let value = visit(self_, m, body);
        escape(self_, value);
        self_.function_roots.resize(self_.function_roots.len - 1);
        return Value { .. };
    }
    if tag == blot_check_core::Tag.project {
        let copied, is_copy = memberCopy(self_, m, id);
        if is_copy {
            // `values.copy` is the prelude's spelling of `@storage.copy`.
            let value = visit(self_, m, n.a);
            if elementHolds(self_, m, n.ty) { escape(self_, value); }
            return Value { fact: copied, exits: value.exits, .. };
        }
        let value = visit(self_, m, n.a);
        if !holds(self_, m, n.ty) { return Value { exits: value.exits, .. }; }
        return Value { origin: value.origin, exits: value.exits, .. };
    }
    if tag == blot_check_core::Tag.array {
        var elements_deep = true;
        var exits = false;
        for child in m.children(id) {
            let value = visitEscaping(self_, m, child);
            exits = exits || value.exits;
            elements_deep = elements_deep && value.origin == 0 && value.fact == deep;
        }
        let fact = freshContainer(self_, m, n.ty, elements_deep);
        return Value { fact: fact, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.record { return recordLiteral(self_, m, id); }
    if tag == blot_check_core::Tag.construct {
        let payload = visitEscaping(self_, m, n.b);
        let literal = n.b != 0 && m.node(n.b).tag == blot_check_core::Tag.record;
        var fact: Fact = none;
        if literal && payload.origin == 0 { fact = payload.fact; }
        return Value { fact: fact, exits: payload.exits, .. };
    }
    if tag == blot_check_core::Tag.array_op { return arrayOp(self_, m, id, false); }
    if tag == blot_check_core::Tag.storage { return storageOp(self_, m, id); }
    let exits = visitChildren(self_, m, id);
    return Value { exits: exits, .. };
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
        let value = visitEscaping(self_, m, child);
        exits = exits || value.exits;
        if !is_record { continue; }
        let destination = m.recordDestinations(id)[index];
        if destination >= shape.b { continue; }
        let declared = m.types.recordField(shape, destination);
        if !holds(self_, m, declared.ty) { continue; }
        var fact = value.fact;
        if value.origin != 0 { fact = none; }
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
    let value = visitEscaping(self_, m, info.value);
    var replacement = value.fact;
    if value.origin != 0 { replacement = none; }
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
        set(self_, successor, replaced);
        return Value { exits: value.exits, .. };
    }
    if !accepts(self_, m, old, selectors) && self_.probing == 0 { self_.rejections.push(Rejection { node: id, span: m.span(id) }); }
    for step in selectors {
        if step.kind == blot_check_core::UpdateKind.index { break; }
        self_.fields.push(m.projection(step.projection).field);
    }
    var next = old;
    if shared { next = weaken(self_, old, self_.fields[mark..]); }
    self_.fields.resize(mark);
    set(self_, successor, next);
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
            let value = visitEscaping(self_, m, children[1]);
            if elementHolds(self_, m, m.typeOf(children[0])) && (value.origin != 0 || value.fact != deep) { sharedInto(self_, m, children[0], []); }
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
                if attempt >= 2 { stored = none; }
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
        set(self_, carry.outgoing, met);
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
    for carry, at in carries { set(self_, carry.iteration, self_.loop_facts[assumed + at]); }
    let start = self_.carried.len;
    for at in 0..count * 2 { self_.carried.push(top); }
    self_.loops.push(LoopFrame { id: id, start: start, len: count });
    let body = visit(self_, m, info.body);
    self_.loops.resize(self_.loops.len - 1);
    for carry, at in carries {
        var backedge: Fact = none;
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
    let join = Join { base: self_.trail.len, merges: merges, changed_start: self_.changed.len, merged_start: self_.merged.len, .. };
    for at in 0..merges.len { self_.merged.push(top); }
    return join;
}
fn arm(self_: Analyzer&, join: Join&, index: i64, result: Value) {
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
        set(self_, merge.result, fact);
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
