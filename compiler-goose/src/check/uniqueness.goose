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
import check.typed_staging;
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
// `holder` borrows from `source`: all of it, or the field `field`. `fact`
// is what the local, or that field, was before; `kills` how often the
// local had been taken for good by then.
struct Loan { holder: u32, source: u32, field: u32, fact: Fact, kills: u32, live: bool }
// A local a closure captured for the length of one call: its fact before,
// and how often it had changed once the closure was made.
struct Captured { binding: u32, fact: Fact, stamp: u32 }
// An expression's result: the fact of a fresh value, or the version whose
// storage it may alias. `exits` means control only leaves the function.
struct Value { fact: Fact = 0, origin: u32 = 0, exits: bool = false }
// A loop being visited: its carries' continue facts, then their break facts,
// at `start` in the shared `carried` stack.
struct LoopFrame { id: u32, start: i64, len: i64 }
struct BlockFrame { id: u32, fact: Fact = 0xffffffff, broken: bool = false }
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
    touch: u32[>..] = [],
    // A name bound to something a local still holds borrows it until its
    // last read (`Loan`). How many live loans a name holds, whether its
    // last read has been seen, and how often each local came to be held
    // by something for good.
    loans: Loan[>..<] = [],
    loan_holds: u32[>..] = [],
    loan_ended: bool[>..] = [],
    kills: u32[>..] = [],
    // The `let` whose value is being read, and the name it binds: a call
    // whose result borrows its arguments lends them to that name.
    let_node: u32 = 0,
    let_holder: u32 = 0,
    // The node whose value is gone when the expression around it has been
    // read: an argument of a call that keeps nothing, or what a plain
    // value is read out of. What its call borrowed for it is given back
    // then (`briefs`).
    brief_node: u32 = 0,
    briefs: Captured[>..<] = [],
    // The locals whose values are arguments of calls still being read: a
    // name among them does not give back what it borrowed until its call
    // is done, even when that was its last read.
    arguments_held: u32[>..<] = [],
    // The node that is read only for a field of it or to update a field of
    // it, not as a whole.
    base_node: u32 = 0,
    // The statement being read: where its block's loans start, and how
    // deep in loops and functions it stands. A call that has run in that
    // same place ends the loans of names read there for the last time.
    statement_mark: i64 = -1,
    statement_loops: i64 = 0,
    statement_roots: i64 = 0,
    statement_tentative: i64 = 0,
    // How many arms of a choice are being read: what an arm does to the
    // facts is taken back when the arms are joined, so no loan ends there.
    tentative: i64 = 0,
    // The locals some reference reads.
    ever_read: bool[>..] = [],
    // For a message that points at the cause: the first part of a record
    // literal that was not its own, and the literal a local was bound to.
    culprits: dictionary<u32, u32> = dictionary<u32, u32> {},
    blame: u32[>..] = [],
    // The versions whose value goes on into another: a branch's into the
    // version after it, a loop's into the next round. They do not borrow.
    flows: bool[>..] = [],
    captured: Captured[>..<] = [],
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
    // The closure that is the whole body of the closure being read, and
    // the parameters the closures around it took over.
    chain: u32 = 0,
    chained: u32[>..<] = [],
    chained_base: i64[>..<] = [],
    // Nodes in callee position, and applications that are another's callee.
    heads: dictionary<u32, bool> = dictionary<u32, bool> {},
    inner: dictionary<u32, bool> = dictionary<u32, bool> {},
    // References to a `lent` function given as an argument.
    lent_arguments: dictionary<u32, bool> = dictionary<u32, bool> {},
    // Whether this module is free of the store `place = value`. Its
    // functions and closures then return values nothing else holds, and it
    // may not write storage it does not own. A module that still has a
    // store is in the old style: only its `own` functions are held to
    // that. This distinction goes when `=` does.
    report_stores: bool = false,
    // Migration aid: with BLOT_EXPLAIN_SHARING set, a result that is not
    // its function's own is reported where the local came to be shared.
    explain: bool = false,
    at: u32 = 0,
    killer: u32[>..] = [],
    owns_cache: dictionary<u32, u8> = dictionary<u32, u8> {},
    // Each binding by unit and number; whether it is a
    // generic function that returns what it was lent (0 unknown, 1 no,
    // 2 yes) and how many arguments its type takes; and each member of a
    // type by the type and the member's name.
    binding_index: dictionary<u64, u32> = dictionary<u64, u32> {},
    // Per binding: 1 for a contract's member, which only passes on what
    // the chosen implementation returns; 2 for an implementation's
    // member, which is held to the result rule in every module, so that a
    // call through the contract can rely on it.
    member_kind: u8[>..] = [],
    reader_state: u8[>..] = [],
    reader_arity: u8[>..] = [],
    identity_ids: dictionary<u64, u32> = dictionary<u64, u32> {},
    in_fork: u32 = 0,
    fork_taint: u32[>..] = [],
    block_taint: dictionary<u32, u32> = dictionary<u32, u32> {},
    non_freezable: bool[>..] = [],
    members: dictionary<u64, u32> = dictionary<u64, u32> {},
    lends_cache: dictionary<u32, u8> = dictionary<u32, u8> {},
    calls_cache: dictionary<u32, u8> = dictionary<u32, u8> {},
    // The root of the function being checked when its result must be owned,
    // and of a contract's member, whose result is its implementation's.
    owned_result: u32 = 0,
    exempt_root: u32 = 0,
    // The root of a contract's member, which may keep what it is lent as
    // its implementation may.
    keeps_root: u32 = 0,
    // The function a `return` being read leaves, or 0.
    leaving_root: u32 = 0,
    // The record or tuple a `return` leaves with: its parts may move
    // fields out of the function's own locals.
    result_node: u32 = 0,
    lent_constant: bool = false,
    // Blocks whose value is the function's result: `return do: ...`.
    tails: u32[>..<] = []
}

// Appends one diagnostic per rejected `:=`, `own` argument and read of a
// spent name in `module`.
fn check(module: const Module&, out: blot_check_core::Diagnostic[>..<]&) {
    var analyzer = Analyzer { .. };
    {
        // Migration aid (tasks/MEMORY_MODEL.md, phase 3): with BLOT_REPORT_STORES set,
        // each store whose place is provably unique is reported as `unchecked`,
        // so a script can turn it into `:=`. It goes with `=`.
        let name = "BLOT_REPORT_STORES\0";
        analyzer.report_stores = blot_native::environment_size(name[0]) >= 0;
        let explaining = "BLOT_EXPLAIN_SHARING\0";
        analyzer.explain = blot_native::environment_size(explaining[0]) >= 0;
    }
    {
        for binding, index in module.bindings {
            analyzer.reader_state.push(0);
            analyzer.reader_arity.push(0);
            analyzer.member_kind.push(0);
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
    for template in module.member_templates { if template.binding < analyzer.member_kind.len { analyzer.member_kind[template.binding] = 1; } }
    for member in module.implementation_members {
        if member.target.unit != 0 && member.target.unit != module.unit { continue; }
        if member.target.binding != 0 && member.target.binding < analyzer.member_kind.len { analyzer.member_kind[member.target.binding] = 2; }
    }
    for at in 0..module.bindings.len { analyzer.facts.push(none); analyzer.touch.push(0); analyzer.killer.push(0); analyzer.loan_holds.push(0); analyzer.loan_ended.push(false); analyzer.ever_read.push(false); analyzer.kills.push(0); analyzer.blame.push(0); analyzer.flows.push(false); analyzer.born.push(0); analyzer.home.push(0); analyzer.stamp.push(0); analyzer.changed_slot.push(-1); analyzer.fork_taint.push(0); analyzer.non_freezable.push(false); }
    for at in 0..module.nodes.len { analyzer.last_read.push(false); }
    for merge in module.merges {
        if merge.then_binding < analyzer.flows.len { analyzer.flows[merge.then_binding] = true; }
        if merge.else_binding < analyzer.flows.len { analyzer.flows[merge.else_binding] = true; }
    }
    for carry in module.loop_carries {
        if carry.incoming < analyzer.flows.len { analyzer.flows[carry.incoming] = true; }
        if carry.backedge < analyzer.flows.len { analyzer.flows[carry.backedge] = true; }
    }
    for body, index in module.bodies {
        if index == 0 || body.root == 0 { continue; }
        analyzer.in_fork = 0;
        // An `own` parameter arrives unique all the way down: every call
        // names this function and gives up an argument that was.
        let own = module.bindings[body.binding].capability_parameters.own;
        for parameter, position in module.bodyParameters(body) {
            if !local(analyzer, parameter.binding) { continue; }
            analyzer.home[parameter.binding] = body.root;
            if own != 0 && body.is_function && position < 32 && (own >> (position as! u32)) & 1 != 0 { set(analyzer, parameter.binding, deep); }
        }
        analyzer.owned_result = 0;
        let kind = analyzer.member_kind[body.binding];
        analyzer.exempt_root = 0;
        analyzer.keeps_root = 0;
        // An entry's result goes to the host, which copies it.
        // So may a `lent` function return what it shares, while `=` exists.
        let named = module.bindings[body.binding];
        let lent = body.is_function && named.kind == blot_reuse_principal_interface::Kind.global && !named.capability_parameters.owned_results && kind == 0;
        let to_host = (body.runtime || body.exported || lent) && own == 0;
        // `lent const again = same` names a `lent` function: not a use of it as a value.
        analyzer.lent_constant = !body.is_function && named.kind == blot_reuse_principal_interface::Kind.global && !named.capability_parameters.owned_results;
        if kind == 1 || to_host { analyzer.exempt_root = body.root; }
        if kind == 1 { analyzer.keeps_root = body.root; }
        if kind != 1 && !to_host && body.is_function { analyzer.owned_result = body.root; }
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
        analyzer.result_node = body.root;
        let value = visit(analyzer, module, body.root);
        analyzer.result_node = 0;
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
    self_.touch[binding] += 1;
}
// A spent version stays spent: nothing gives its storage back.
fn kill(self_: Analyzer&, binding: u32) {
    if !local(self_, binding) { return; }
    // Something else holds it now, for good. If the name borrowed its
    // value, what it borrowed from stays shared too.
    self_.touch[binding] += 1;
    self_.kills[binding] += 1;
    if self_.explain && self_.facts[binding] != none { self_.killer[binding] = self_.at; }
    if self_.loan_holds[binding] != 0 {
        for &loan in self_.loans { if loan.live && loan.holder == binding { loan.live = false; } }
        self_.loan_holds[binding] = 0;
    }
    if self_.facts[binding] == spent { return; }
    // A part that was given away stays given away.
    if partSpent(self_, self_.facts[binding]) { set(self_, binding, spent); return; }
    set(self_, binding, none);
}
// `holder` is bound to what `source` still holds: the whole of it, or its
// field `symbol`. The local, or that field, is shared while the name is in
// use and gets its fact back afterwards.
fn borrow(self_: Analyzer&, holder: u32, source: u32, symbol: u32) {
    if !local(self_, holder) || !local(self_, source) || self_.facts[source] == spent || self_.loan_holds[source] != 0 { kill(self_, source); return; }
    var saved = self_.facts[source];
    let whole = wholeLoan(self_, source);
    if symbol == 0 {
        set(self_, source, none);
    } else {
        let mark = self_.fields.len;
        self_.fields.push(symbol);
        if whole >= 0 {
            // A name borrows the whole local: the field comes out of the
            // fact that name gives back.
            saved = field(self_, self_.loans[whole].fact, symbol);
            let weakened = replace(self_, self_.loans[whole].fact, self_.fields[mark..], none);
            self_.loans[whole].fact = weakened;
        } else {
            saved = field(self_, saved, symbol);
            let weakened = replace(self_, self_.facts[source], self_.fields[mark..], none);
            set(self_, source, weakened);
        }
        self_.fields.resize(mark);
    }
    self_.loans.push(Loan { holder: holder, source: source, field: symbol, fact: saved, kills: self_.kills[source], live: true });
    self_.loan_holds[holder] += 1;
    self_.loan_ended[holder] = false;
}
// The first name that borrows the whole of `source`, as an index into the
// loans, or -1. It holds the fact the local gets back.
fn wholeLoan(self_: const Analyzer&, source: u32) -> i64 {
    for at in 0..self_.loans.len {
        let loan = self_.loans[at];
        if loan.live && loan.source == source && loan.field == 0 && loan.kills == self_.kills[source] { return at; }
    }
    return -1;
}
// Ends the loans made since `mark` whose name has been read for the last
// time, or all of them when their block ends.
fn giveBackLoans(self_: Analyzer&, mark: i64, all: bool) {
    for at in mark..self_.loans.len {
        let loan = self_.loans[at];
        if !loan.live || (!all && !self_.loan_ended[loan.holder]) { continue; }
        if !all {
            var in_use = false;
            for held in self_.arguments_held { in_use = in_use || held == loan.holder; }
            if in_use { continue; }
        }
        self_.loans[at].live = false;
        if self_.loan_holds[loan.holder] != 0 { self_.loan_holds[loan.holder] -= 1; }
        if !local(self_, loan.source) || self_.kills[loan.source] != loan.kills || self_.facts[loan.source] == spent { continue; }
        // Another name still borrows the same thing: it gives back
        // instead. The earliest of them holds the fact to give back.
        var passed = false;
        for other in 0..self_.loans.len {
            let still = self_.loans[other];
            if !still.live || still.source != loan.source || still.field != loan.field || still.kills != loan.kills { continue; }
            if other > at { self_.loans[other].fact = loan.fact; }
            passed = true;
            break;
        }
        if passed { continue; }
        if loan.field == 0 {
            set(self_, loan.source, loan.fact);
        } else {
            let scratch = self_.fields.len;
            self_.fields.push(loan.field);
            let whole = wholeLoan(self_, loan.source);
            if whole >= 0 {
                // The field goes back into what the name that borrows
                // the whole local gives back.
                let restored = replace(self_, self_.loans[whole].fact, self_.fields[scratch..], loan.fact);
                self_.loans[whole].fact = restored;
            } else {
                let restored = replace(self_, self_.facts[loan.source], self_.fields[scratch..], loan.fact);
                set(self_, loan.source, restored);
            }
            self_.fields.resize(scratch);
        }
    }
    if all { self_.loans.resize(mark); }
}
// `successor` is the next version of `source` after an update whose path
// starts at the field `symbol` (0: none). The names that borrow from the
// old version borrow from the new one, unless the update replaced what
// they borrowed.
fn moveLoans(self_: Analyzer&, source: u32, successor: u32, symbol: u32) {
    if !local(self_, source) || !local(self_, successor) { return; }
    for &loan in self_.loans {
        if !loan.live || loan.source != source { continue; }
        if loan.field == 0 || loan.field == symbol || self_.kills[source] != loan.kills {
            loan.live = false;
            if self_.loan_holds[loan.holder] != 0 { self_.loan_holds[loan.holder] -= 1; }
            continue;
        }
        loan.source = successor;
        loan.kills = self_.kills[successor];
    }
}
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
    if self_.dry && local(self_, binding) { self_.reads.push(binding); self_.reads.push(node); self_.ever_read[binding] = true; }
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
    if self_.function_roots.len == 0 { return false; }
    let root = self_.function_roots[self_.function_roots.len - 1];
    // A loop gives a local of an earlier iteration away again, unless the
    // function is being left.
    if self_.born[binding] != loop_id && self_.leaving_root != root { return false; }
    return self_.home[binding] == root;
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
// The fact a part of the function's result gets. A field of a local that
// leaves with the function moves out of it: `return { rows: world.rows }`.
// The field is spent from there on, so it cannot leave twice.
fn takenPart(self_: Analyzer&, m: const Module&, node: u32, value: Value) -> Fact {
    if value.origin != 0 && !self_.dry && m.node(node).tag == blot_check_core::Tag.project && local(self_, value.origin) && self_.function_roots.len != 0 && self_.facts[value.origin] != spent {
        let target, found = place(self_, m, node);
        if found && target.len != 0 && target.binding == value.origin && self_.home[value.origin] == self_.function_roots[self_.function_roots.len - 1] {
            let fact = partFact(self_, self_.facts[value.origin], target.fields[..target.len]);
            if fact != spent && fact != none {
                let given = replace(self_, self_.facts[value.origin], target.fields[..target.len], spent);
                set(self_, value.origin, given);
                return fact;
            }
        }
    }
    return taken(self_, m, node, value);
}
// The value of an arm that names a local at its last read is that local's
// own value, moved out: `_ => world` beside arms that return a new world.
fn armValue(self_: Analyzer&, m: const Module&, node: u32, value: Value) -> Value {
    if node == 0 || value.origin == 0 || !moves(self_, m, node, value.origin) { return value; }
    let fact = self_.facts[value.origin];
    kill(self_, value.origin);
    return Value { fact: fact, exits: value.exits, .. };
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
// Whether some part of a value with `fact` was given away: the whole of
// it, or a field that an `own` parameter took and nothing was put back in.
recursive fn partSpent(self_: const Analyzer&, fact: Fact) -> bool {
    if fact == spent { return true; }
    if fact < first_record || fact == top { return false; }
    let value = self_.records[fact - first_record];
    if value.default_ == spent { return true; }
    for at in 0..value.len { if partSpent(self_, self_.entries[value.start + at].fact) { return true; } }
    return false;
}
// Whether a field of a value with `fact` is lent or shared: a name still
// borrows it, or something else holds it.
recursive fn partShared(self_: const Analyzer&, fact: Fact) -> bool {
    if fact < first_record || fact == top { return false; }
    let value = self_.records[fact - first_record];
    for at in 0..value.len {
        let part = self_.entries[value.start + at].fact;
        if part == none || partShared(self_, part) { return true; }
    }
    return false;
}
// The fact of the part of a value with `fact` that `fields` select.
fn partFact(self_: const Analyzer&, fact: Fact, fields: const u32[:]) -> Fact {
    var part = fact;
    for symbol in fields { part = field(self_, part, symbol); }
    return part;
}
fn record(self_: const Analyzer&, fact: Fact) -> Record { return self_.records[fact - first_record]; }
fn field(self_: const Analyzer&, fact: Fact, symbol: u32) -> Fact {
    if fact == spent { return spent; }
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
    if fact == spent { return spent; }
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

// Depth affects the nesting-limit answer. Each root query has fixed arguments;
// entering a nominal definition gives its substitution and recursion stack a
// fresh scope. An instantiation query uses the concrete type as its second key.
struct WalkNode { ty: u32, other: u64, depth: i64 }
fn hash(node: WalkNode) -> u64 {
    return ::hash_combine(::hash_combine(::hash(node.ty), ::hash(node.other)), ::hash(node.depth));
}
struct WalkMemo {
    direct_visits: i64 = 16,
    scope: u64 = 0,
    next_scope: u64 = 0,
    answers: dictionary<WalkNode, bool> = dictionary<WalkNode, bool> {}
}
fn tracking(memo: WalkMemo&, depth: i64) -> bool {
    if depth > 64 { return false; }
    if memo.direct_visits == 0 { return true; }
    memo.direct_visits -= 1;
    return false;
}
fn enterNominal(memo: WalkMemo&) -> u64 {
    let parent = memo.scope;
    memo.next_scope += 1;
    memo.scope = memo.next_scope;
    return parent;
}

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
fn holdsIn(self_: Analyzer&, m: const Module&, ty: u32, variables: const u32[:], arguments: const bool[:], depth: i64) -> bool {
    var memo = WalkMemo {};
    return holdsInMemo(self_, m, ty, variables, arguments, depth, memo);
}
recursive fn holdsInMemo(self_: Analyzer&, m: const Module&, ty: u32, variables: const u32[:], arguments: const bool[:], depth: i64, memo: WalkMemo&) -> bool {
    if !tracking(memo, depth) { return holdsInNode(self_, m, ty, variables, arguments, depth, memo); }
    let key = WalkNode { ty, memo.scope, depth };
    let cached .= memo.answers.get(key);
    if cached { let answer: bool = cached; return answer; }
    let answer = holdsInNode(self_, m, ty, variables, arguments, depth, memo);
    memo.answers.insert(key, answer);
    return answer;
}
recursive fn holdsInNode(self_: Analyzer&, m: const Module&, ty: u32, variables: const u32[:], arguments: const bool[:], depth: i64, memo: WalkMemo&) -> bool {
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
    if (n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound) { return false; }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.function { return true; }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) {
            if holdsInMemo(self_, m, item, variables, arguments, depth + 1, memo) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b {
            if holdsInMemo(self_, m, m.types.recordField(n, index).ty, variables, arguments, depth + 1, memo) { return true; }
        }
        return false;
    }
    if n.tag != blot_check_types::Tag.nominal { return true; }
    if blot_check_storage_types::isLengthLiteral(n.a, n.b) { return false; }
    let storage_kind = blot_check_storage_types::identity(n.a, n.b);
    if storage_kind.present {
        if storage_kind.value == blot_check_storage_types::shared { return false; }
        return true;
    }
    if n.a == 0xffffffff { return true; }
    let index, found = nominalIndex(self_, m, n.a, n.b);
    if !found { return true; }
    let nominal = m.nominal(index);
    if nominal.is_opaque { return true; }
    let own = m.types.list(nominal.variables);
    let given = m.types.nominalArguments(n);
    if own.len != given.len || own.len > 16 { return true; }
    var bits: bool[16] = [false; 16];
    for argument, at in given { bits[at] = holdsInMemo(self_, m, argument, variables, arguments, depth + 1, memo); }
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
    let parent_scope = enterNominal(memo);
    for constructor in m.nominalConstructors(index) {
        let payload = m.constructor(constructor).payload;
        if payload != 0 && holdsInMemo(self_, m, payload, own, bits[..own.len], depth + 1, memo) { result = true; break; }
    }
    memo.scope = parent_scope;
    self_.expanding.resize(self_.expanding.len - 1);
    return result;
}
// Whether a value of `ty` can hold an array it owns (`want_owned`), or a
// part that only borrows: a view, a reference, a link, a cursor or a
// function. Type variables do neither. A shape this cannot read (an opaque
// type, an effect type) counts as borrowing: its results are not checked
// and not promised. So does growable storage, until `=` is gone.
fn owns(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    let known .= self_.owns_cache.get(ty);
    if known { let bit: u8 = known; return bit != 0; }
    let result = partsIn(self_, m, ty, 0, [], [], 0);
    var bit: u8 = 0;
    if result { bit = 1; }
    self_.owns_cache.insert(ty, bit);
    return result;
}
fn lends(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    let known .= self_.lends_cache.get(ty);
    if known { let bit: u8 = known; return bit != 0; }
    let result = partsIn(self_, m, ty, 1, [], [], 0);
    var bit: u8 = 0;
    if result { bit = 1; }
    self_.lends_cache.insert(ty, bit);
    return result;
}
// Whether a value of type `ty` can hold a function.
fn calls(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    let known .= self_.calls_cache.get(ty);
    if known { let bit: u8 = known; return bit != 0; }
    let result = partsIn(self_, m, ty, 2, [], [], 0);
    var bit: u8 = 0;
    if result { bit = 1; }
    self_.calls_cache.insert(ty, bit);
    return result;
}
// Whether `ty` has a part that owns an array (`want` 0), a part that
// borrows (1) or a function (2).
fn partsIn(self_: Analyzer&, m: const Module&, ty: u32, want: u8, variables: const u32[:], arguments: const bool[:], depth: i64) -> bool {
    var memo = WalkMemo {};
    return partsInMemo(self_, m, ty, want, variables, arguments, depth, memo);
}
recursive fn partsInMemo(self_: Analyzer&, m: const Module&, ty: u32, want: u8, variables: const u32[:], arguments: const bool[:], depth: i64, memo: WalkMemo&) -> bool {
    if !tracking(memo, depth) { return partsInNode(self_, m, ty, want, variables, arguments, depth, memo); }
    let key = WalkNode { ty, memo.scope, depth };
    let cached .= memo.answers.get(key);
    if cached { let answer: bool = cached; return answer; }
    let answer = partsInNode(self_, m, ty, want, variables, arguments, depth, memo);
    memo.answers.insert(key, answer);
    return answer;
}
recursive fn partsInNode(self_: Analyzer&, m: const Module&, ty: u32, want: u8, variables: const u32[:], arguments: const bool[:], depth: i64, memo: WalkMemo&) -> bool {
    if ty == blot_check_types::unit || ty == blot_check_types::boolean || ty == blot_check_types::u32_type || ty == blot_check_types::f32_type || ty == blot_check_types::never { return false; }
    let want_owned = want == 0;
    if depth > 64 || ty >= m.types.nodes.len { return want == 1; }
    for variable, at in variables { if variable == ty { return arguments[at]; } }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return false; }
    if n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound { return false; }
    if n.tag == blot_check_types::Tag.function { return want != 0; }
    if n.tag == blot_check_types::Tag.cursor { return want == 1; }
    if n.tag == blot_check_types::Tag.usage { return partsInMemo(self_, m, n.a, want, variables, arguments, depth + 1, memo); }
    // A list is never written in place, so it owns only what its
    // elements do.
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list {
        if want_owned && n.tag == blot_check_types::Tag.array { return true; }
        return partsInMemo(self_, m, n.a, want, variables, arguments, depth + 1, memo);
    }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) {
            if partsInMemo(self_, m, item, want, variables, arguments, depth + 1, memo) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b {
            if partsInMemo(self_, m, m.types.recordField(n, index).ty, want, variables, arguments, depth + 1, memo) { return true; }
        }
        return false;
    }
    if n.tag != blot_check_types::Tag.nominal { return want == 1; }
    // A GrowArray and a ResizeArray own their storage as an array does. A
    // view, a reference and a link borrow.
    if blot_check_storage_types::isLengthLiteral(n.a, n.b) { return false; }
    if blot_check_storage_types::identity(n.a, n.b).present {
        let kind = blot_check_storage_types::identity(n.a, n.b).value;
        if kind == blot_check_storage_types::shared {
            return false;
        }
        if kind == blot_check_storage_types::grow || kind == blot_check_storage_types::resize || kind == blot_check_storage_types::sized_array || kind == blot_check_storage_types::sized_grow || kind == blot_check_storage_types::sized_resize {
            if want == 0 { return true; }
            for argument in m.types.nominalArguments(n) { if partsInMemo(self_, m, argument, want, variables, arguments, depth + 1, memo) { return true; } }
            return false;
        }
        if want != 2 { return want == 1; }
        for argument in m.types.nominalArguments(n) { if partsInMemo(self_, m, argument, want, variables, arguments, depth + 1, memo) { return true; } }
        return false;
    }
    if n.a == 0xffffffff { return want == 1; }
    let index, found = nominalIndex(self_, m, n.a, n.b);
    if !found { return want == 1; }
    let nominal = m.nominal(index);
    if nominal.is_opaque { return want == 1; }
    let own = m.types.list(nominal.variables);
    let given = m.types.nominalArguments(n);
    if own.len != given.len || own.len > 16 { return want == 1; }
    var bits: bool[16] = [false; 16];
    for argument, at in given { bits[at] = partsInMemo(self_, m, argument, want, variables, arguments, depth + 1, memo); }
    // A recursive occurrence at the same arguments adds nothing its first
    // expansion lacks; one at other arguments might.
    for outer in self_.expanding {
        if outer.unit == n.a && outer.decl == n.b {
            if outer.len != own.len { return want == 1; }
            for at in 0..own.len { if outer.arguments[at] != bits[at] { return want == 1; } }
            return false;
        }
    }
    self_.expanding.push(Expansion { unit: n.a, decl: n.b, arguments: bits, len: own.len });
    var result = false;
    let parent_scope = enterNominal(memo);
    for constructor in m.nominalConstructors(index) {
        let payload = m.constructor(constructor).payload;
        if payload != 0 && partsInMemo(self_, m, payload, want, own, bits[..own.len], depth + 1, memo) { result = true; break; }
    }
    memo.scope = parent_scope;
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
// The place a borrowed value comes out of: `world.rows` for `world.rows`,
// for an element or a field of an element of it, and for a view of it.
fn source(self_: const Analyzer&, m: const Module&, id: u32) -> Place, bool {
    var cursor = id;
    loop {
        let target, found = place(self_, m, cursor);
        if found { return target, true; }
        let n = m.node(cursor);
        if n.tag == blot_check_core::Tag.project { cursor = n.a; continue; }
        if n.tag == blot_check_core::Tag.array_op {
            let operation = m.arrayOperation(cursor);
            if operation != blot_backend_collection_ops::Op.get && operation != blot_backend_collection_ops::Op.identity { return Place { .. }, false; }
        } else if n.tag == blot_check_core::Tag.storage {
            let operation, unknown = blot_check_storage_ops::opFromCode(n.c);
            if unknown != blot_error::Error.none || (operation != blot_check_storage_ops::Op.view && operation != blot_check_storage_ops::Op.read) { return Place { .. }, false; }
        } else {
            return Place { .. }, false;
        }
        let children = m.children(cursor);
        if children.len == 0 { return Place { .. }, false; }
        cursor = children[0];
    }
}
// `fact` with the storage at `fields` no longer known to own its elements:
// a store or push put a value there that may be shared.
recursive fn weaken(self_: Analyzer&, fact: Fact, fields: const u32[:]) -> Fact {
    if fields.len == 0 {
        if fact == deep { return shell; }
        if fact == spent { return spent; }
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
    if self_.explain && (tag == blot_check_core::Tag.call || tag == blot_check_core::Tag.apply || tag == blot_check_core::Tag.bind || tag == blot_check_core::Tag.closure) { self_.at = id; }
    // The name a `let` binds this node's value to, when it may borrow.
    var lends_to: u32 = 0;
    if self_.let_node != 0 {
        if self_.let_node == id { lends_to = self_.let_holder; }
        self_.let_node = 0;
    }
    // Whether this node's value is gone with the expression around it.
    var brief = false;
    if self_.brief_node != 0 {
        brief = self_.brief_node == id;
        self_.brief_node = 0;
    }
    var based = false;
    if self_.base_node != 0 {
        based = self_.base_node == id;
        self_.base_node = 0;
    }
    if tag == blot_check_core::Tag.state_provider || tag == blot_check_core::Tag.effect_provider || tag == blot_check_core::Tag.handle {
        // A provider names the operations it answers; that is not a use
        // of them as functions.
        let start = self_.children.len;
        {
            var list = blot_eval_body_recipe::Pending { items: self_.children, limit: 0x7fffffffffffffff };
            let error = blot_eval_body_recipe::appendChildren(list, m, id, false);
            assert(error == blot_error::Error.none);
        }
        for child in self_.children[start..] { if m.node(child).tag == blot_check_core::Tag.operation_value { self_.heads.insert(child, true); } }
        self_.children.resize(start);
    }
    if tag == blot_check_core::Tag.constructor_function || tag == blot_check_core::Tag.primitive_function || tag == blot_check_core::Tag.operation_value {
        if !self_.heads.contains(id) { keeperValue(self_, m, id, n.ty); }
        return Value { .. };
    }
    if tag == blot_check_core::Tag.constant || tag == blot_check_core::Tag.type_constructor || tag == blot_check_core::Tag.invalid { return Value { .. }; }
    if tag == blot_check_core::Tag.panic { return Value { exits: true, .. }; }
    if tag == blot_check_core::Tag.reference {
        let target = m.reference(id);
        // A function that takes over a parameter is only ever called in
        // full, which `apply` and `call` see before this.
        if !self_.lent_arguments.contains(id) && !self_.lent_constant {
            lentValue(self_, m, id);
            {
                // An entry function may return what it shares, so it cannot
                // stand for a function whose result is the caller's alone.
                let named = calleeBinding(self_, m, id);
                if named != 0 && !self_.heads.contains(id) && m.bindings[named].kind != blot_reuse_principal_interface::Kind.local && m.bindings[named].kind != blot_reuse_principal_interface::Kind.parameter && !trusted(self_, m, named) {
                    if finalOwns(self_, m, n.ty) { reject(self_, m, id, blot_check_core::Code.lent_result_value); }
                }
            }
        }
        if target.unit != 0 && target.unit != m.unit { return Value { .. }; }
        if !local(self_, target.binding) { return Value { .. }; }
        read(self_, target.binding, id);
        if !self_.dry && self_.last_read[id] && self_.loan_holds[target.binding] != 0 { self_.loan_ended[target.binding] = true; }
        if self_.facts[target.binding] == spent { reject(self_, m, id, blot_check_core::Code.spent_value); return Value { .. }; }
        // Read as a whole while a field of it is given away.
        if !based && !self_.dry && partSpent(self_, self_.facts[target.binding]) { reject(self_, m, id, blot_check_core::Code.spent_value); return Value { .. }; }
        return Value { origin: target.binding, .. };
    }
    if tag == blot_check_core::Tag.suite {
        let exits = statements(self_, m, id);
        return Value { exits: exits, .. };
    }
    if tag == blot_check_core::Tag.block_ { return block_(self_, m, id); }
    if tag == blot_check_core::Tag.fork_ { return forkNode(self_, m, id); }
    if tag == blot_check_core::Tag.bind {
        let value = m.node(n.b);
        if value.tag == blot_check_core::Tag.update && !m.updateInfo(n.b).store { return update(self_, m, n.b, n.a); }
        // A `let` may borrow: another name for what a local holds, or the
        // result of a call that borrows its arguments. A name rebound with
        // `:=` does not: its value goes on into later versions that no
        // reference shows.
        let borrows = !self_.dry && n.c == 0 && local(self_, n.a) && !self_.flows[n.a];
        let outer_node = self_.let_node;
        let outer_holder = self_.let_holder;
        self_.let_node = 0;
        if borrows { self_.let_node = n.b; self_.let_holder = n.a; }
        var result = Value { .. };
        if value.tag == blot_check_core::Tag.array_op { var to: u32 = 0; if borrows { to = n.a; } self_.let_node = 0; result = arrayOp(self_, m, n.b, true, false, to); } else { result = visit(self_, m, n.b); }
        self_.let_node = outer_node;
        self_.let_holder = outer_holder;
        if borrows && result.origin != 0 && !moves(self_, m, n.b, result.origin) {
            define(self_, n.a, none);
            var symbol: u32 = 0;
            let target, found = place(self_, m, n.b);
            if found && target.binding == result.origin && target.len != 0 { symbol = target.fields[0]; }
            borrow(self_, n.a, result.origin, symbol);
            if !self_.ever_read[n.a] && self_.loan_holds[n.a] != 0 { self_.loan_ended[n.a] = true; }
            if self_.in_fork != 0 { setForkTaint(self_, n.a, nodeTaint(self_, m, n.b, 0)); }
            if closureNonFreezable(self_, m, n.b) { setNonFreezable(self_, n.a, true); }
            return Value { exits: result.exits, .. };
        }
        let fact = taken(self_, m, n.b, result);
        define(self_, n.a, fact);
        if local(self_, n.a) {
            self_.blame[n.a] = n.b;
            if self_.in_fork != 0 { setForkTaint(self_, n.a, nodeTaint(self_, m, n.b, 0)); }
            if closureNonFreezable(self_, m, n.b) { setNonFreezable(self_, n.a, true); }
        }
        return Value { exits: result.exits, .. };
    }
    if tag == blot_check_core::Tag.update { return update(self_, m, id, 0); }
    if tag == blot_check_core::Tag.return_ {
        let leaves = self_.function_roots.len != 0 && n.b == self_.function_roots[self_.function_roots.len - 1];
        // A local that leaves with the function has no later use, so the
        // value keeps the local's fact; so does one a tail block breaks with.
        let tail = leaves && n.a != 0 && m.node(n.a).tag == blot_check_core::Tag.block_;
        if tail { self_.tails.push(n.a); }
        let logged = self_.reads.len;
        let outer_leaving = self_.leaving_root;
        if leaves { self_.leaving_root = n.b; }
        let outer_result = self_.result_node;
        self_.result_node = 0;
        if n.a != 0 && !tail && (leaves || (self_.tails.len != 0 && self_.tails[self_.tails.len - 1] == n.b)) { self_.result_node = n.a; }
        let result = visit(self_, m, n.a);
        self_.result_node = outer_result;
        self_.leaving_root = outer_leaving;
        if tail { self_.tails.resize(self_.tails.len - 1); }
        // Nothing runs after a return: its reads are the last on its path.
        if leaves && self_.dry { lastReads(self_, logged); }
        var fact: Fact = none;
        let ends = leaves || (self_.tails.len != 0 && self_.tails[self_.tails.len - 1] == n.b);
        // So does a field of such a local: `return stream.output`.
        var part = Place { .. };
        if result.origin != 0 && ends && !self_.dry && m.node(n.a).tag == blot_check_core::Tag.project && self_.home[result.origin] == self_.function_roots[self_.function_roots.len - 1] {
            let target, found = place(self_, m, n.a);
            if found && target.len != 0 && target.binding == result.origin && local(self_, target.binding) { part = target; }
        }
        // Where the function is left nothing runs after, so the local is
        // not marked as shared: on an early return inside a branch that
        // mark would outlive the branch and keep what names borrowed from
        // the local before it from ever being given back.
        if result.origin != 0 && ends && !self_.dry && m.node(n.a).tag == blot_check_core::Tag.reference && self_.home[result.origin] == self_.function_roots[self_.function_roots.len - 1] {
            fact = self_.facts[result.origin];
            if !leaves { kill(self_, result.origin); }
        } else if part.len != 0 {
            fact = partFact(self_, self_.facts[result.origin], part.fields[..part.len]);
            if fact == spent { fact = none; }
            if !leaves { kill(self_, result.origin); }
        } else {
            fact = taken(self_, m, n.a, result);
        }
        if leaves && n.a != 0 && !result.exits && resultChecked(self_, m, n.b, m.typeOf(n.a)) && !ownedAs(self_, m, fact, m.typeOf(n.a), 0) { reject(self_, m, culprit(self_, m, n.a), blot_check_core::Code.result_not_owned); }
        if self_.in_fork != 0 && n.a != 0 && !result.exits {
            let taint = nodeTaint(self_, m, n.a, 0);
            if leaves && taint >= self_.in_fork && (holds(self_, m, m.typeOf(n.a)) || blot_check_storage_types::isShared(m.types, m.typeOf(n.a))) {
                reject(self_, m, culprit(self_, m, n.a), blot_check_core::Code.result_not_owned);
            } else if taint != 0 {
                markBlockTaint(self_, n.b, taint);
            }
        }
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
        // Taking a value apart: the parts of a value nothing else holds
        // are each their name's alone.
        let whole = visit(self_, m, n.b);
        if taken(self_, m, n.b, whole) == deep { ownPattern(self_, m, n.a, 0); }
        if self_.in_fork != 0 {
            let taint = nodeTaint(self_, m, n.b, 0);
            if taint != 0 { taintPattern(self_, m, n.a, taint, 0); }
        }
        if n.c != 0 {
            let mark = self_.trail.len;
            self_.tentative += 1;
            let fallback = visit(self_, m, n.c);
            self_.tentative -= 1;
            if fallback.exits { undo(self_, mark); }
        }
        return Value { .. };
    }
    if tag == blot_check_core::Tag.loop_ { return loop_(self_, m, id); }
    if tag == blot_check_core::Tag.break_ { return breakNode(self_, m, id); }
    if tag == blot_check_core::Tag.closure {
        // A spent capture is reported where the body reads it.
        let body = m.closure(id).body;
        let parameter = m.closure(id).parameter.binding;
        // `func (a: own A) -> (b: B) => …` is a closure whose body is a
        // closure. A call gives all its arguments at once (a parameter
        // taken over cannot be given without the rest), so the inner one
        // runs once with what the outer one took: it keeps the fact.
        let link = self_.chain == id;
        for captured in m.closureCaptures(id) {
            read(self_, captured, id);
            var carried = false;
            if link { for outer in self_.chained { if outer == captured { carried = true; } } }
            if carried { self_.home[captured] = body; } else { kill(self_, captured); }
        }
        if local(self_, parameter) {
            self_.home[parameter] = body;
            if typeTaking(m, n.ty) & 1 != 0 { define(self_, parameter, deep); self_.home[parameter] = body; }
        }
        var inner_closure = body;
        if m.node(inner_closure).tag == blot_check_core::Tag.return_ { inner_closure = m.node(inner_closure).a; }
        let outer_chain = self_.chain;
        let chained_mark = self_.chained.len;
        if !link { self_.chained_base.push(chained_mark); }
        // The chain goes on through a parameter that is not taken over
        // (`-> (k: U32)`) while it carries one that was.
        let takes = local(self_, parameter) && unique(self_.facts[parameter]);
        let carries = link && self_.chained_base.len != 0 && self_.chained.len > self_.chained_base[self_.chained_base.len - 1];
        if m.node(inner_closure).tag == blot_check_core::Tag.closure && (takes || carries) {
            self_.chain = inner_closure;
            if takes { self_.chained.push(parameter); }
        } else {
            self_.chain = 0;
        }
        self_.function_roots.push(body);
        let logged = self_.reads.len;
        // A body that is one expression is the function's result.
        let outer_result = self_.result_node;
        self_.result_node = body;
        let value = visit(self_, m, body);
        self_.result_node = outer_result;
        self_.chain = outer_chain;
        if !link { self_.chained.resize(self_.chained_base[self_.chained_base.len - 1]); self_.chained_base.resize(self_.chained_base.len - 1); }
        // The closure's own locals end with its body. What it captured is
        // read again whenever it runs, so those reads are never the last.
        if self_.dry {
            lastReads(self_, logged);
            for captured in m.closureCaptures(id) { read(self_, captured, id); }
        }
        if !value.exits { ownedResult(self_, m, body, value); }
        escape(self_, value);
        self_.function_roots.resize(self_.function_roots.len - 1);
        return Value { .. };
    }
    if tag == blot_check_core::Tag.project {
        if m.dispatchSignature(id) != 0 {
            // `value.member` without its arguments would hold a value
            // the member takes over for any number of calls.
            let named = calleeBinding(self_, m, id);
            if named != 0 && m.bindings[named].capability_parameters.own & 1 != 0 { reject(self_, m, id, blot_check_core::Code.own_function_value); }
        }
        let copied, is_copy = memberCopy(self_, m, id);
        if is_copy {
            // `values.copy` is the prelude's spelling of `@storage.copy`.
            let value = visit(self_, m, n.a);
            if elementHolds(self_, m, n.ty) { escape(self_, value); }
            return Value { fact: copied, exits: value.exits, .. };
        }
        if m.dispatchSignature(id) != 0 {
            let member = calleeBinding(self_, m, id);
            let lent = member != 0 && lentHere(self_, m, member, calleeType(m, id));
            if member != 0 { reader(self_, m, member); }
            if trusted(self_, m, member) && self_.reader_arity[member] <= 1 {
                // `value.member` with no further argument is the whole call.
                let keeps = lends(self_, m, n.ty);
                let ends = self_.briefs.len;
                if !keeps && !lent { self_.brief_node = n.a; }
                let value = visit(self_, m, n.a);
                self_.brief_node = 0;
                if lent { return Value { origin: value.origin, exits: value.exits, .. }; }
                if keeps { held(self_, m, n.a, value, lends_to, brief); } else { endBriefs(self_, ends); }
                var fact: Fact = none;
                if owns(self_, m, n.ty) { fact = deep; }
                return Value { fact: fact, exits: value.exits, .. };
            }
            lentValue(self_, m, id);
        }
        let value = receiver(self_, m, n.a, n.ty, brief, lends_to);
        if !self_.dry && value.origin != 0 {
            // A field that an `own` parameter took is read again only
            // after something was put back in it.
            let target, found = place(self_, m, id);
            if found && target.binding == value.origin && local(self_, target.binding) && self_.facts[target.binding] != spent && partFact(self_, self_.facts[target.binding], target.fields[..target.len]) == spent {
                reject(self_, m, id, blot_check_core::Code.spent_value);
                return Value { exits: value.exits, .. };
            }
        }
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
            elements_deep = elements_deep && (fact == deep || ownedAs(self_, m, fact, m.typeOf(child), 0));
        }
        let fact = freshContainer(self_, m, n.ty, elements_deep);
        return Value { fact: fact, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.product {
        // A tuple nothing else holds: every part that can hold an array
        // is fresh or moved in.
        var parts_deep = true;
        var exits = false;
        let leaving = id == self_.result_node;
        for child in m.children(id) {
            if leaving { self_.result_node = child; }
            let value = visit(self_, m, child);
            var fact: Fact = none;
            if leaving { fact = takenPart(self_, m, child, value); } else { fact = taken(self_, m, child, value); }
            exits = exits || value.exits;
            parts_deep = parts_deep && ownedAs(self_, m, fact, m.typeOf(child), 0);
        }
        var fact: Fact = none;
        if parts_deep { fact = deep; }
        return Value { fact: fact, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.record { return recordLiteral(self_, m, id); }
    if tag == blot_check_core::Tag.record_merge {
        // The merged record holds the parts of both: it is its holder's
        // own when each side was.
        let left = visit(self_, m, n.a);
        let left_fact = taken(self_, m, n.a, left);
        let right = visit(self_, m, n.b);
        let right_fact = taken(self_, m, n.b, right);
        var fact: Fact = none;
        if ownedAs(self_, m, left_fact, m.typeOf(n.a), 0) && ownedAs(self_, m, right_fact, m.typeOf(n.b), 0) { fact = deep; }
        return Value { fact: fact, exits: left.exits || right.exits, .. };
    }
    if tag == blot_check_core::Tag.construct {
        if id == self_.result_node { self_.result_node = n.b; }
        let payload = visit(self_, m, n.b);
        let literal = n.b != 0 && m.node(n.b).tag == blot_check_core::Tag.record;
        let held = taken(self_, m, n.b, payload);
        var fact: Fact = none;
        if literal && payload.origin == 0 { fact = held; }
        // A constructor holds what its payload does: nothing without one,
        // and a payload nothing else holds stays that way inside it.
        if n.b == 0 || ownedAs(self_, m, held, m.typeOf(n.b), 0) { fact = deep; }
        return Value { fact: fact, exits: payload.exits, .. };
    }
    if tag == blot_check_core::Tag.staging && (n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.read_input) || n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.evaluate)) {
        let input = visit(self_, m, n.a);
        return Value { fact: deep, exits: input.exits, .. };
    }
    if tag == blot_check_core::Tag.array_op { return arrayOp(self_, m, id, false, brief, lends_to); }
    if tag == blot_check_core::Tag.storage { return storageOp(self_, m, id); }
    if tag == blot_check_core::Tag.call && m.call(id).own != 0 {
        let exits = ownArguments(self_, m, m.call(id).arguments, m.call(id).own, n.ty, lends_to, brief);
        // Every return of the callee gave a value nothing else holds.
        return Value { fact: deep, exits: exits, .. };
    }
    if tag == blot_check_core::Tag.apply {
        // `f a b` and `a.f b` reach a function through its value: a
        // chain of applications, one argument each. Its type says which
        // parameters it takes over.
        var arguments: u32[32] = [0; 32];
        var count: i64 = 0;
        var callee = id;
        while count < 32 && m.node(callee).tag == blot_check_core::Tag.apply {
            arguments[count] = m.node(callee).b;
            count += 1;
            callee = m.node(callee).a;
        }
        let member = m.node(callee).tag == blot_check_core::Tag.project && m.dispatchSignature(callee) != 0;
        var taking: u64 = 0;
        if m.node(callee).tag != blot_check_core::Tag.apply {
            if member {
                // The member the value's type selects says it itself; the
                // signature the checker wrote for the use need not.
                let named = calleeBinding(self_, m, callee);
                if named != 0 && m.bindings[named].capability_parameters.own != 0 {
                    taking = ((m.bindings[named].capability_parameters.own_count as u64) << 32) | m.bindings[named].capability_parameters.own;
                } else {
                    taking = typeTaking(m, m.dispatchSignature(callee));
                }
            } else {
                taking = typeTaking(m, m.typeOf(callee));
            }
        }
        let mask = taking as! u32;
        // The value of `value.member` is the first argument.
        if mask != 0 && member && count < 32 {
            arguments[count] = m.node(callee).a;
            count += 1;
        }
        if mask != 0 && count == (taking >> 32) as i64 {
            for at in 0..count / 2 {
                let other = arguments[count - 1 - at];
                arguments[count - 1 - at] = arguments[at];
                arguments[at] = other;
            }
            var exits = false;
            if !member {
                self_.heads.insert(callee, true);
                let held = visit(self_, m, callee);
                exits = held.exits;
            }
            exits = ownArguments(self_, m, arguments[..count], mask, n.ty, lends_to, brief) || exits;
            // Every return of the callee gave a value nothing else holds.
            return Value { fact: deep, exits: exits, .. };
        }
        // Given a parameter it takes over but not all its arguments, the
        // function would hold the argument for any number of calls.
        if mask != 0 && count < (taking >> 32) as i64 && count < 32 && mask & (((1 as u32) << (count as! u32)) - 1) != 0 && !self_.inner.contains(id) {
            reject(self_, m, id, blot_check_core::Code.own_function_value);
        }
    }
    if tag == blot_check_core::Tag.call || tag == blot_check_core::Tag.apply {
        // A call only borrows its arguments, and the arrays its result
        // owns are the caller's alone. A part of the result that borrows
        // (a view, a function) may hold the arguments, so then they are
        // shared from here on.
        var head = id;
        var count: i64 = 0;
        while m.node(head).tag == blot_check_core::Tag.apply { head = m.node(head).a; count += 1; if m.node(head).tag == blot_check_core::Tag.apply { self_.inner.insert(head, true); } }
        if tag == blot_check_core::Tag.apply { self_.heads.insert(head, true); }
        if tag == blot_check_core::Tag.apply && self_.inner.contains(id) {
            // Part of a longer application whose callee is not known: the
            // arguments are shared, as phase 1 had it.
            let exits = visitChildren(self_, m, id);
            return Value { exits: exits, .. };
        }
        let keeper = m.node(head).tag == blot_check_core::Tag.constructor_function || m.node(head).tag == blot_check_core::Tag.primitive_function || m.node(head).tag == blot_check_core::Tag.operation_value;
        if tag == blot_check_core::Tag.apply && keeper && !self_.inner.contains(id) {
            // A constructor or an effect operation given only some of its
            // arguments is a function that keeps the others.
            if m.types.node(n.ty).tag == blot_check_types::Tag.function { keeperValue(self_, m, head, m.typeOf(head)); }
            if m.node(head).tag == blot_check_core::Tag.operation_value {
                // The handler may keep what the operation is given, and
                // what it resumes with is still its own.
                var exits = false;
                var cursor = id;
                while m.node(cursor).tag == blot_check_core::Tag.apply {
                    let child = m.node(cursor).b;
                    let value = visit(self_, m, child);
                    let given = taken(self_, m, child, value);
                    if !keeping(self_) && ((owns(self_, m, m.typeOf(child)) && !ownedAs(self_, m, given, m.typeOf(child), 0)) || lentHolder(self_, m, child)) { reject(self_, m, child, blot_check_core::Code.kept_value); }
                    escape(self_, value);
                    exits = exits || value.exits;
                    cursor = m.node(cursor).a;
                }
                return Value { exits: exits, .. };
            }
        }
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
        // A call given a `lent` function is as little to be relied on as
        // the function: it shares its arguments and its result is not
        // unique.
        let lent_given = lentArgument(self_, m, id);
        if !lent_given && trusted(self_, m, binding) && reader(self_, m, binding) && count >= self_.reader_arity[binding] as i64 && lentHere(self_, m, binding, used_at) {
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
        // Whether the callee's result is the caller's alone: every
        // function's is, except an entry function's. A constructor keeps
        // its argument, and so may a primitive.
        let head_tag = m.node(head).tag;
        var unresolved = false;
        var known = !lent_given && trusted(self_, m, binding);
        // A `lent` function (and an entry called like any function) may
        // return what it was lent but keeps nothing: `kept_value` holds in
        // it too. With all its arguments, its result holds them as a
        // result with a part that borrows does, and is never unique.
        var returns_lent = false;
        if !known && !lent_given && tag == blot_check_core::Tag.call && binding != 0 && m.bindings[binding].kind != blot_reuse_principal_interface::Kind.local && m.bindings[binding].kind != blot_reuse_principal_interface::Kind.parameter {
            known = true;
            returns_lent = true;
        }
        // A `lent` or entry function given only some of its arguments is
        // a function value too.
        if !known && !lent_given && tag == blot_check_core::Tag.apply && head_tag == blot_check_core::Tag.reference && binding != 0 && m.bindings[binding].kind != blot_reuse_principal_interface::Kind.local && m.bindings[binding].kind != blot_reuse_principal_interface::Kind.parameter && !self_.inner.contains(id) && finalOwns(self_, m, n.ty) {
            reject(self_, m, id, blot_check_core::Code.lent_result_value);
        }
        if !known && !lent_given && tag == blot_check_core::Tag.apply {
            // Every function value obeys the result rule: a closure, a
            // local or a parameter that holds one, a record's field, what
            // a call or a choice gave.
            // Not where the result has a part that borrows: a `lent`
            // function may stand for such a function value.
            let plain = !lends(self_, m, n.ty);
            if head_tag == blot_check_core::Tag.closure { known = true; }
            if plain && (head_tag == blot_check_core::Tag.call || head_tag == blot_check_core::Tag.if_value || head_tag == blot_check_core::Tag.match_ || head_tag == blot_check_core::Tag.block_) { known = true; }
            if plain && head_tag == blot_check_core::Tag.project && m.dispatchSignature(head) == 0 { known = true; }
            // A field of a record whose type is not known yet holds a
            // function value like any other. What it returns is not known
            // either, so it may borrow the arguments (`unresolved`).
            if plain && head_tag == blot_check_core::Tag.project && m.dispatchSignature(head) != 0 && binding == 0 { known = true; unresolved = true; }
            if head_tag == blot_check_core::Tag.reference && binding != 0 {
                let kind = m.bindings[binding].kind;
                if plain && (kind == blot_reuse_principal_interface::Kind.local || kind == blot_reuse_principal_interface::Kind.parameter) { known = true; }
                if kind == blot_reuse_principal_interface::Kind.local {
                    let made = m.bindings[binding].initializer;
                    if made != 0 && made < m.nodes.len && m.node(made).tag == blot_check_core::Tag.closure { known = true; }
                }
            }
        }
        if known {
            // With all its arguments the call only borrows them. A part
            // of the result that borrows (a function, when arguments are
            // still missing) may hold them, so then they are shared.
            let holder = lends(self_, m, n.ty) || (unresolved && openType(m, n.ty, 0)) || (returns_lent && (holds(self_, m, n.ty) || openType(m, n.ty, 0)));
            var exits = false;
            let base = self_.captured.len;
            let ends = self_.briefs.len;
            let held_base = self_.arguments_held.len;
            if tag == blot_check_core::Tag.call {
                for child in m.call(id).arguments {
                    let value = lend(self_, m, child, holder, lends_to, brief);
                    exits = exits || value.exits;
                }
            } else {
                var arguments: u32[32] = [0; 32];
                var given: i64 = 0;
                var cursor = id;
                while given < 32 && m.node(cursor).tag == blot_check_core::Tag.apply {
                    arguments[given] = m.node(cursor).b;
                    given += 1;
                    cursor = m.node(cursor).a;
                }
                if cursor != head {
                    // Too long to read as one call.
                    self_.captured.resize(base);
                    self_.briefs.resize(ends);
                    self_.arguments_held.resize(held_base);
                    let all = visitChildren(self_, m, id);
                    return Value { exits: all, .. };
                }
                // The value of `value.member` is the first argument.
                var callee = Value { .. };
                if head_tag == blot_check_core::Tag.project { callee = lend(self_, m, m.node(head).a, holder, lends_to, brief); } else { callee = lend(self_, m, head, holder, lends_to, brief); }
                exits = callee.exits;
                for back in 0..given {
                    let value = lend(self_, m, arguments[given - 1 - back], holder, lends_to, brief);
                    exits = exits || value.exits;
                }
            }
            self_.arguments_held.resize(held_base);
            giveBack(self_, base);
            if !holder {
                endBriefs(self_, ends);
                // A name read for the last time by this call, which kept
                // nothing, gives back what it borrowed.
                if !self_.dry && self_.statement_mark >= 0 && self_.loops.len == self_.statement_loops && self_.function_roots.len == self_.statement_roots && self_.tentative == self_.statement_tentative { giveBackLoans(self_, self_.statement_mark, false); }
            }
            var fact: Fact = none;
            // (a result of a type that is not known yet is its caller's too)
            if !returns_lent && (owns(self_, m, n.ty) || openType(m, n.ty, 0)) { fact = deep; }
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

// Whether `binding` is a named function of a module without stores: its
// result is the caller's alone, and it keeps nothing it is lent.
fn trusted(self_: const Analyzer&, m: const Module&, binding: u32) -> bool {
    var current = binding;
    for step in 0..8 {
        if current == 0 || current >= m.bindings.len { return false; }
        if m.bindings[current].capability_parameters.owned_results || self_.member_kind[current] == 1 { return true; }
        // `const replace = array.replace` names the same function.
        if m.bindings[current].kind != blot_reuse_principal_interface::Kind.global { return false; }
        var made = m.bindings[current].initializer;
        let body = m.bindings[current].body_id;
        if made == 0 && body != 0 && body < m.bodies.len && !m.bodies[body].is_function { made = m.bodies[body].root; }
        if made != 0 && made < m.nodes.len && m.node(made).tag == blot_check_core::Tag.return_ { made = m.node(made).a; }
        if made == 0 || made >= m.nodes.len || m.node(made).tag != blot_check_core::Tag.reference { return false; }
        let target = m.reference(made);
        let found .= self_.binding_index.get(((target.unit as u64) << 32) | target.binding);
        if !found { return false; }
        let index: u32 = found;
        current = index;
    }
    return false;
}
// Whether the storage `node` names is a local's own: nothing else holds
// it, so writing it in place is the local's business alone.
fn storageOwned(self_: const Analyzer&, m: const Module&, node: u32) -> bool {
    let target, found = place(self_, m, node);
    if !found || !local(self_, target.binding) { return false; }
    var fact = self_.facts[target.binding];
    if fact == spent { return false; }
    for at in 0..target.len { fact = field(self_, fact, target.fields[at]); }
    return unique(fact);
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
fn occurs(m: const Module&, variable: u32, ty: u32, data: bool, depth: i64) -> bool {
    var memo = WalkMemo {};
    return occursMemo(m, variable, ty, data, depth, memo);
}
recursive fn occursMemo(m: const Module&, variable: u32, ty: u32, data: bool, depth: i64, memo: WalkMemo&) -> bool {
    if !tracking(memo, depth) { return occursNode(m, variable, ty, data, depth, memo); }
    let key = WalkNode { ty, 0, depth };
    let cached .= memo.answers.get(key);
    if cached { let answer: bool = cached; return answer; }
    let answer = occursNode(m, variable, ty, data, depth, memo);
    memo.answers.insert(key, answer);
    return answer;
}
recursive fn occursNode(m: const Module&, variable: u32, ty: u32, data: bool, depth: i64, memo: WalkMemo&) -> bool {
    if ty == variable { return true; }
    if ty == 0 || ty >= m.types.nodes.len { return false; }
    if depth > 64 { return true; }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.absent || n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return false; }
    if n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound { return false; }
    if n.tag == blot_check_types::Tag.function {
        if data { return false; }
        return occursMemo(m, variable, n.a, data, depth + 1, memo) || occursMemo(m, variable, n.b, data, depth + 1, memo);
    }
    // `own T` in a function type's parameter, and the other usage wrappers.
    if n.tag == blot_check_types::Tag.usage { return occursMemo(m, variable, n.a, data, depth + 1, memo); }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor { return occursMemo(m, variable, n.a, data, depth + 1, memo); }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) { if occursMemo(m, variable, item, data, depth + 1, memo) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b { if occursMemo(m, variable, m.types.recordField(n, index).ty, data, depth + 1, memo) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.nominal {
        for argument in m.types.nominalArguments(n) { if occursMemo(m, variable, argument, data, depth + 1, memo) { return true; } }
        return false;
    }
    return true;
}
// Whether `ty` has a type variable where data is: a value of such a type
// may hold storage once the variable has its type. Inside a generic body it
// is read as plain data, but it is not given to an `own` parameter out of
// what the function was only lent.
fn openType(m: const Module&, ty: u32, depth: i64) -> bool {
    var memo = WalkMemo {};
    return openTypeMemo(m, ty, depth, memo);
}
recursive fn openTypeMemo(m: const Module&, ty: u32, depth: i64, memo: WalkMemo&) -> bool {
    if !tracking(memo, depth) { return openTypeNode(m, ty, depth, memo); }
    let key = WalkNode { ty, 0, depth };
    let cached .= memo.answers.get(key);
    if cached { let answer: bool = cached; return answer; }
    let answer = openTypeNode(m, ty, depth, memo);
    memo.answers.insert(key, answer);
    return answer;
}
recursive fn openTypeNode(m: const Module&, ty: u32, depth: i64, memo: WalkMemo&) -> bool {
    if ty == 0 || ty >= m.types.nodes.len { return false; }
    if depth > 64 { return true; }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.variable || n.tag == blot_check_types::Tag.rigid || n.tag == blot_check_types::Tag.bound { return true; }
    if n.tag == blot_check_types::Tag.usage || n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor { return openTypeMemo(m, n.a, depth + 1, memo); }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) { if openTypeMemo(m, item, depth + 1, memo) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b { if openTypeMemo(m, m.types.recordField(n, index).ty, depth + 1, memo) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.nominal {
        for argument in m.types.nominalArguments(n) { if openTypeMemo(m, argument, depth + 1, memo) { return true; } }
        return false;
    }
    return false;
}
// Whether `variable` occurs in `ty` inside growable storage, a reference or
// a link: storage a function can put a value into for later.
fn occursInSink(m: const Module&, variable: u32, ty: u32, inside: bool, depth: i64) -> bool {
    var memo = WalkMemo {};
    return occursInSinkMemo(m, variable, ty, inside, depth, memo);
}
recursive fn occursInSinkMemo(m: const Module&, variable: u32, ty: u32, inside: bool, depth: i64, memo: WalkMemo&) -> bool {
    if !tracking(memo, depth) { return occursInSinkNode(m, variable, ty, inside, depth, memo); }
    var state: u32 = 0;
    if inside { state = 1; }
    let key = WalkNode { ty, state, depth };
    let cached .= memo.answers.get(key);
    if cached { let answer: bool = cached; return answer; }
    let answer = occursInSinkNode(m, variable, ty, inside, depth, memo);
    memo.answers.insert(key, answer);
    return answer;
}
recursive fn occursInSinkNode(m: const Module&, variable: u32, ty: u32, inside: bool, depth: i64, memo: WalkMemo&) -> bool {
    if ty == variable { return inside; }
    if ty == 0 || ty >= m.types.nodes.len || depth > 64 { return false; }
    let n = m.types.node(ty);
    if n.tag == blot_check_types::Tag.function { return occursInSinkMemo(m, variable, n.a, inside, depth + 1, memo) || occursInSinkMemo(m, variable, n.b, inside, depth + 1, memo); }
    if n.tag == blot_check_types::Tag.usage { return occursInSinkMemo(m, variable, n.a, inside, depth + 1, memo); }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor { return occursInSinkMemo(m, variable, n.a, inside, depth + 1, memo); }
    if n.tag == blot_check_types::Tag.product {
        for item in m.types.list(blot_check_types::List { start: n.a, len: n.b }) { if occursInSinkMemo(m, variable, item, inside, depth + 1, memo) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.record {
        for index in 0..n.b { if occursInSinkMemo(m, variable, m.types.recordField(n, index).ty, inside, depth + 1, memo) { return true; } }
        return false;
    }
    if n.tag == blot_check_types::Tag.nominal {
        let storage = blot_check_storage_types::identity(n.a, n.b);
        let sink = inside || (storage.present && storage.value != blot_check_storage_types::view);
        for argument in m.types.nominalArguments(n) { if occursInSinkMemo(m, variable, argument, sink, depth + 1, memo) { return true; } }
        return false;
    }
    return false;
}
// Whether a function of type `root` with `arity` parameters can keep a value
// of type `variable` past the call: in its result, or in storage one of its
// parameters gives it.
fn keeps(m: const Module&, root: u32, arity: i64, variable: u32) -> bool {
    var parameter = root;
    for position in 0..arity {
        if occursInSink(m, variable, m.types.node(parameter).a, false, 0) { return true; }
        parameter = m.types.node(parameter).b;
    }
    return occurs(m, variable, parameter, false, 0);
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
        if !keeps(m, scheme.root, arity as i64, variable) { continue; }
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
fn instanceOwns(self_: Analyzer&, m: const Module&, pattern: u32, actual: u32, variable: u32, depth: i64) -> bool {
    var memo = WalkMemo {};
    var occurrences = WalkMemo {};
    return instanceOwnsMemo(self_, m, pattern, actual, variable, depth, memo, occurrences);
}
recursive fn instanceOwnsMemo(self_: Analyzer&, m: const Module&, pattern: u32, actual: u32, variable: u32, depth: i64, memo: WalkMemo&, occurrences: WalkMemo&) -> bool {
    if !tracking(memo, depth) { return instanceOwnsNode(self_, m, pattern, actual, variable, depth, memo, occurrences); }
    let key = WalkNode { pattern, actual, depth };
    let cached .= memo.answers.get(key);
    if cached { let answer: bool = cached; return answer; }
    let answer = instanceOwnsNode(self_, m, pattern, actual, variable, depth, memo, occurrences);
    memo.answers.insert(key, answer);
    return answer;
}
recursive fn instanceOwnsNode(self_: Analyzer&, m: const Module&, pattern: u32, actual: u32, variable: u32, depth: i64, memo: WalkMemo&, occurrences: WalkMemo&) -> bool {
    if pattern == variable { return owns(self_, m, actual); }
    if !occursMemo(m, variable, pattern, false, 0, occurrences) { return false; }
    if depth > 64 || actual == 0 || actual >= m.types.nodes.len || pattern >= m.types.nodes.len { return true; }
    let p = m.types.node(pattern);
    let a = m.types.node(actual);
    if p.tag != a.tag { return true; }
    if p.tag == blot_check_types::Tag.function { return instanceOwnsMemo(self_, m, p.a, a.a, variable, depth + 1, memo, occurrences) || instanceOwnsMemo(self_, m, p.b, a.b, variable, depth + 1, memo, occurrences); }
    if p.tag == blot_check_types::Tag.usage { return instanceOwnsMemo(self_, m, p.a, a.a, variable, depth + 1, memo, occurrences); }
    if p.tag == blot_check_types::Tag.array || p.tag == blot_check_types::Tag.list || p.tag == blot_check_types::Tag.cursor { return instanceOwnsMemo(self_, m, p.a, a.a, variable, depth + 1, memo, occurrences); }
    if p.tag == blot_check_types::Tag.product {
        if p.b != a.b { return true; }
        let left = m.types.list(blot_check_types::List { start: p.a, len: p.b });
        let right = m.types.list(blot_check_types::List { start: a.a, len: a.b });
        for item, at in left { if instanceOwnsMemo(self_, m, item, right[at], variable, depth + 1, memo, occurrences) { return true; } }
        return false;
    }
    if p.tag == blot_check_types::Tag.record {
        if p.b != a.b { return true; }
        for index in 0..p.b { if instanceOwnsMemo(self_, m, m.types.recordField(p, index).ty, m.types.recordField(a, index).ty, variable, depth + 1, memo, occurrences) { return true; } }
        return false;
    }
    if p.tag == blot_check_types::Tag.nominal {
        let left = m.types.nominalArguments(p);
        let right = m.types.nominalArguments(a);
        if p.a != a.a || p.b != a.b || left.len != right.len { return true; }
        for item, at in left { if instanceOwnsMemo(self_, m, item, right[at], variable, depth + 1, memo, occurrences) { return true; } }
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
        if !keeps(m, scheme.root, arity, variable) { continue; }
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
// A constructor, a primitive or an effect operation used as a value: it
// keeps its argument, in its result or in a handler, so it may not be one
// where that owns an array.
// Whether the function being read is one that may keep what it was lent:
// a `lent` function or an entry, outside any closure in it.
fn keeping(self_: const Analyzer&) -> bool {
    return self_.function_roots.len != 0 && self_.keeps_root != 0 && self_.function_roots[self_.function_roots.len - 1] == self_.keeps_root;
}
// Whether a caller would take the result of a function value of type `ty`,
// given all its arguments, to be its own: it owns an array and has no part
// that borrows. A call through a function value whose result borrows
// shares its arguments and is not unique, whatever the function does.
fn finalOwns(self_: Analyzer&, m: const Module&, ty: u32) -> bool {
    var result = ty;
    var steps: i64 = 0;
    while steps < 64 && result != 0 && result < m.types.nodes.len && m.types.node(result).tag == blot_check_types::Tag.function { result = m.types.node(result).b; steps += 1; }
    return steps != 0 && owns(self_, m, result) && !lends(self_, m, result);
}
// An argument of a call that only borrows. A closure written as the
// argument holds what it captured for the length of the call: nothing
// the callee does can keep a function it was lent, unless its result
// borrows (`holder`). So what it captured is unique again afterwards.
recursive fn lend(self_: Analyzer&, m: const Module&, child: u32, holder: bool, lends_to: u32, brief: bool) -> Value {
    let from = self_.captured.len;
    if !holder && m.node(child).tag == blot_check_core::Tag.closure {
        for binding in m.closureCaptures(child) {
            if local(self_, binding) && self_.facts[binding] != spent { self_.captured.push(Captured { binding: binding, fact: self_.facts[binding], stamp: 0 }); }
        }
    }
    // The call keeps nothing: what this argument's own call borrowed is
    // gone when the call has run.
    // A call that keeps its arguments in its result hands on where that
    // result goes.
    if !holder || brief { self_.brief_node = child; } else if lends_to != 0 { self_.let_node = child; self_.let_holder = lends_to; }
    let value = visit(self_, m, child);
    self_.brief_node = 0;
    self_.let_node = 0;
    for at in from..self_.captured.len { self_.captured[at].stamp = self_.touch[self_.captured[at].binding]; }
    if value.origin != 0 && local(self_, value.origin) { self_.arguments_held.push(value.origin); }
    if holder { held(self_, m, child, value, lends_to, brief); }
    return value;
}
// The result of a call may hold `value`, its argument at `child`. Bound by
// a `let`, that name borrows it and gives it back, at once when nothing
// reads the name. Gone with the expression around the call, it is given
// back there. Otherwise it is shared for good.
fn held(self_: Analyzer&, m: const Module&, child: u32, value: Value, lends_to: u32, brief: bool) {
    if value.origin == 0 { return; }
    if lends_to != 0 {
        var symbol: u32 = 0;
        let target, found = place(self_, m, child);
        if found && target.binding == value.origin && target.len != 0 { symbol = target.fields[0]; }
        borrow(self_, lends_to, value.origin, symbol);
        if local(self_, lends_to) && !self_.ever_read[lends_to] && self_.loan_holds[lends_to] != 0 { self_.loan_ended[lends_to] = true; }
        return;
    }
    if brief && local(self_, value.origin) && self_.facts[value.origin] != spent {
        let fact = self_.facts[value.origin];
        set(self_, value.origin, none);
        self_.briefs.push(Captured { binding: value.origin, fact: fact, stamp: self_.touch[value.origin] });
        return;
    }
    escape(self_, value);
}
// Gives back what was borrowed since `base` for values that are gone now.
fn endBriefs(self_: Analyzer&, base: i64) {
    for at in base..self_.briefs.len {
        let entry = self_.briefs[at];
        if self_.touch[entry.binding] == entry.stamp && self_.facts[entry.binding] != spent { set(self_, entry.binding, entry.fact); }
    }
    self_.briefs.resize(base);
}
// Reads `child`, which a field or an element of type `ty` is read out of.
// A plain value keeps nothing of `child`, so what a call borrowed for
// `child` is given back; anything else stands for `child` in what is
// around it.
recursive fn receiver(self_: Analyzer&, m: const Module&, child: u32, ty: u32, brief: bool, lends_to: u32) -> Value {
    if ty == 0 || !holds(self_, m, ty) {
        let ends = self_.briefs.len;
        self_.brief_node = child;
        self_.base_node = child;
        let value = visit(self_, m, child);
        self_.brief_node = 0;
        self_.base_node = 0;
        endBriefs(self_, ends);
        return value;
    }
    if brief { self_.brief_node = child; } else if lends_to != 0 { self_.let_node = child; self_.let_holder = lends_to; }
    self_.base_node = child;
    let value = visit(self_, m, child);
    self_.brief_node = 0;
    self_.let_node = 0;
    self_.base_node = 0;
    return value;
}
fn giveBack(self_: Analyzer&, base: i64) {
    for at in base..self_.captured.len {
        let entry = self_.captured[at];
        // Only if nothing else happened to the local since.
        if self_.touch[entry.binding] == entry.stamp && self_.facts[entry.binding] != spent { set(self_, entry.binding, entry.fact); }
    }
    self_.captured.resize(base);
}
// Whether `node` reads a function the function was lent: a parameter it
// does not own, or a capture, that can hold one. Keeping it would keep
// what the function captured shared after the call that lent it.
fn lentHolder(self_: Analyzer&, m: const Module&, node: u32) -> bool {
    if !calls(self_, m, m.typeOf(node)) { return false; }
    let target, found = place(self_, m, node);
    if !found || !local(self_, target.binding) { return false; }
    if self_.function_roots.len != 0 && self_.home[target.binding] != self_.function_roots[self_.function_roots.len - 1] { return true; }
    return m.bindings[target.binding].kind == blot_reuse_principal_interface::Kind.parameter && !unique(self_.facts[target.binding]);
}
// Whether one of the arguments of the call or application `id` names a
// `lent` or entry function. Such an argument is not a use of the function
// as a value that anything relies on.
fn lentArgument(self_: Analyzer&, m: const Module&, id: u32) -> bool {
    var found = false;
    if m.node(id).tag == blot_check_core::Tag.call {
        for child in m.call(id).arguments { if lentFunction(self_, m, child) { self_.lent_arguments.insert(child, true); found = true; } }
        return found;
    }
    var cursor = id;
    var steps: i64 = 0;
    while steps < 64 && m.node(cursor).tag == blot_check_core::Tag.apply {
        let child = m.node(cursor).b;
        if lentFunction(self_, m, child) { self_.lent_arguments.insert(child, true); found = true; }
        cursor = m.node(cursor).a;
        steps += 1;
    }
    return found;
}
fn lentFunction(self_: Analyzer&, m: const Module&, node: u32) -> bool {
    if m.node(node).tag != blot_check_core::Tag.reference { return false; }
    if m.types.node(m.typeOf(node)).tag != blot_check_types::Tag.function { return false; }
    let named = calleeBinding(self_, m, node);
    if named == 0 { return false; }
    let kind = m.bindings[named].kind;
    if kind == blot_reuse_principal_interface::Kind.local || kind == blot_reuse_principal_interface::Kind.parameter { return false; }
    return !trusted(self_, m, named);
}
// Gives every name `pattern` binds a value of its own.
recursive fn ownPattern(self_: Analyzer&, m: const Module&, pattern: u32, depth: i64) {
    if pattern == 0 || pattern >= m.patterns.len || depth > 64 { return; }
    let shape = m.pattern(pattern);
    if shape.tag == blot_check_core::PatternTag.bind { define(self_, shape.a, deep); return; }
    if shape.tag == blot_check_core::PatternTag.product { for child in m.patternChildren(pattern) { ownPattern(self_, m, child, depth + 1); } return; }
    if shape.tag == blot_check_core::PatternTag.constructor || shape.tag == blot_check_core::PatternTag.record_payload { ownPattern(self_, m, shape.b, depth + 1); }
}
// Where to point for a value that is not its holder's own: the part of
// the record it was built from that something else holds, if one is known.
fn culprit(self_: const Analyzer&, m: const Module&, node: u32) -> u32 {
    var at = node;
    for step in 0..8 {
        if at == 0 || at >= m.nodes.len { return node; }
        let n = m.node(at);
        var literal = at;
        if n.tag == blot_check_core::Tag.return_ && n.a != 0 { at = n.a; continue; }
        if n.tag == blot_check_core::Tag.reference {
            let target = m.reference(at);
            if self_.explain && (target.unit == 0 || target.unit == m.unit) && local(self_, target.binding) && self_.killer[target.binding] != 0 { return self_.killer[target.binding]; }
            if (target.unit != 0 && target.unit != m.unit) || !local(self_, target.binding) || self_.blame[target.binding] == 0 { return at; }
            literal = self_.blame[target.binding];
        }
        if literal < m.nodes.len && m.node(literal).tag == blot_check_core::Tag.construct && m.node(literal).b != 0 { literal = m.node(literal).b; }
        let found .= self_.culprits.get(literal);
        // Only a part that was never the record's own explains it; a local
        // that was shared after it was bound is named where it is used.
        if !found { return at; }
        let part: u32 = found;
        at = part;
    }
    return at;
}
fn keeperValue(self_: Analyzer&, m: const Module&, node: u32, ty: u32) {
    var result = ty;
    var takes = false;
    var sinks = false;
    var steps: i64 = 0;
    while steps < 64 && result != 0 && result < m.types.nodes.len && m.types.node(result).tag == blot_check_types::Tag.function {
        let parameter = m.types.node(result).a;
        takes = takes || owns(self_, m, parameter);
        sinks = sinks || lends(self_, m, parameter);
        result = m.types.node(result).b;
        steps += 1;
    }
    var keeps = owns(self_, m, result);
    if m.node(node).tag == blot_check_core::Tag.primitive_function { keeps = keeps || (takes && sinks); } else { keeps = keeps || takes; }
    if keeps { reject(self_, m, node, blot_check_core::Code.lent_result_value); }
}
fn lentValue(self_: Analyzer&, m: const Module&, node: u32) {
    let binding = calleeBinding(self_, m, node);
    if binding == 0 { return; }
    if lentHere(self_, m, binding, calleeType(m, node)) { reject(self_, m, node, blot_check_core::Code.lent_result_value); }
}
// Which parameters a function of type `ty` takes over, and how many it
// has: the count above bit 32, one bit a parameter below.
fn typeTaking(m: const Module&, ty: u32) -> u64 {
    var mask: u32 = 0;
    var arity: u64 = 0;
    var cursor = ty;
    while arity < 32 && cursor != 0 && cursor < m.types.nodes.len && m.types.node(cursor).tag == blot_check_types::Tag.function {
        let parameter = m.types.node(cursor).a;
        if parameter < m.types.nodes.len && m.types.node(parameter).tag == blot_check_types::Tag.usage && m.types.node(parameter).b == blot_check_types::usageCode(blot_parse_ast::usagekind_own) { mask |= (1 as u32) << (arity as! u32); }
        arity += 1;
        cursor = m.types.node(cursor).b;
    }
    return (arity << 32) | mask;
}
// The arguments of a full call of a function that takes over the parameters
// in `mask`. An `own` argument must be a fresh value, or a local that holds
// its value alone; the local is spent. Inside a loop the local must belong
// to the same iteration, or the next one would give it away again.
// The other arguments are lent as in any call. While the call's arguments
// are read, what a lent one names counts as shared, so the same value
// cannot be lent and given in one call; it has its fact back after the call.
recursive fn ownArguments(self_: Analyzer&, m: const Module&, arguments: const u32[:], mask: u32, result: u32, lends_to: u32, brief: bool) -> bool {
    var exits = false;
    let holder = lends(self_, m, result);
    let base = self_.captured.len;
    let ends = self_.briefs.len;
    let held_base = self_.arguments_held.len;
    var guarded: u32[32] = [0; 32];
    var guard_saved: u32[32] = [0; 32];
    var guard_kills: u32[32] = [0; 32];
    var guard_fields: u32[256] = [0; 256];
    var guard_len: i64[32] = [0; 32];
    var guards: i64 = 0;
    // A value is given when the call happens, after its other arguments
    // are computed: those are read first, then the ones given are judged.
    for phase in 0..2 {
    if phase == 1 && !holder && !self_.dry && self_.statement_mark >= 0 && self_.loops.len == self_.statement_loops && self_.function_roots.len == self_.statement_roots && self_.tentative == self_.statement_tentative {
        // The other arguments are computed. A name they read for the last
        // time gives back what it borrowed before the given ones are
        // judged, unless an argument still being read holds it.
        giveBackLoans(self_, self_.statement_mark, false);
    }
    for child, position in arguments {
        let ty = m.typeOf(child);
        let open = openType(m, ty, 0);
        let lent = position >= 32 || (mask >> (position as! u32)) & 1 == 0 || (!holds(self_, m, ty) && !open);
        if lent != (phase == 0) { continue; }
        if lent {
            let value = lend(self_, m, child, holder, lends_to, brief);
            exits = exits || value.exits;
            if !holder && guards < 32 && local(self_, value.origin) && self_.facts[value.origin] != spent {
                var path = Place { .. };
                let target, found = source(self_, m, child);
                if found && target.binding == value.origin { path = target; }
                let saved = partFact(self_, self_.facts[value.origin], path.fields[..path.len]);
                let shared = replace(self_, self_.facts[value.origin], path.fields[..path.len], none);
                set(self_, value.origin, shared);
                guarded[guards] = value.origin;
                guard_saved[guards] = saved;
                guard_kills[guards] = self_.kills[value.origin];
                guard_len[guards] = path.len;
                for at in 0..path.len { guard_fields[guards * 8 + at] = path.fields[at]; }
                guards += 1;
            } else if !holder {
                escape(self_, value);
            }
            continue;
        }
        var named: u32 = 0;
        if m.node(child).tag == blot_check_core::Tag.reference {
            let target = m.reference(child);
            if (target.unit == 0 || target.unit == m.unit) && local(self_, target.binding) { named = target.binding; }
        }
        // A field of a local can be given too: `world.pool := grown
        // world.pool`. The field is spent until something is put back.
        var part = Place { .. };
        if named == 0 {
            let target, found = place(self_, m, child);
            if found && target.len != 0 && local(self_, target.binding) { part = target; }
        }
        var was_spent = named != 0 && self_.facts[named] == spent;
        if part.len != 0 && partFact(self_, self_.facts[part.binding], part.fields[..part.len]) == spent { was_spent = true; }
        let value = visit(self_, m, child);
        exits = exits || value.exits;
        if was_spent { continue; }
        var accepted = false;
        var loop_id: u32 = 0;
        if self_.loops.len != 0 { loop_id = self_.loops[self_.loops.len - 1].id; }
        if value.origin == 0 {
            accepted = ownedAs(self_, m, value.fact, ty, 0);
        } else if named != 0 {
            accepted = self_.born[named] == loop_id && ownedAs(self_, m, self_.facts[named], ty, 0);
            // What a type variable stands for may hold storage: a name of
            // such a type is given only when it is known to be its own.
            if open && !unique(self_.facts[named]) && self_.facts[named] < first_record { accepted = false; }
            // Nor while a name still borrows one of its fields.
            if open && partShared(self_, self_.facts[named]) { accepted = false; }
        } else if part.len != 0 && value.origin == part.binding {
            let fact = partFact(self_, self_.facts[part.binding], part.fields[..part.len]);
            accepted = self_.born[part.binding] == loop_id && fact != spent && ownedAs(self_, m, fact, ty, 0);
            if open && !unique(fact) && fact < first_record { accepted = false; }
            if open && partShared(self_, fact) { accepted = false; }
        }
        if !accepted { reject(self_, m, child, blot_check_core::Code.own_argument); }
        if accepted && named != 0 {
            set(self_, named, spent);
        } else if accepted && part.len != 0 && value.origin == part.binding {
            let given = replace(self_, self_.facts[part.binding], part.fields[..part.len], spent);
            set(self_, part.binding, given);
        } else {
            escape(self_, value);
        }
    }
    }
    for at in 0..guards {
        let binding = guarded[at];
        if self_.kills[binding] != guard_kills[at] || self_.facts[binding] == spent { continue; }
        let restored = replace(self_, self_.facts[binding], guard_fields[at * 8..at * 8 + guard_len[at]], guard_saved[at]);
        set(self_, binding, restored);
    }
    self_.arguments_held.resize(held_base);
    giveBack(self_, base);
    if !holder {
        endBriefs(self_, ends);
        if !self_.dry && self_.statement_mark >= 0 && self_.loops.len == self_.statement_loops && self_.function_roots.len == self_.statement_roots && self_.tentative == self_.statement_tentative { giveBackLoans(self_, self_.statement_mark, false); }
    }
    return exits;
}
// The value a function with an `own` parameter ends with, when it ends
// without a `return`.
fn ownedResult(self_: Analyzer&, m: const Module&, node: u32, value: Value) {
    var fact = value.fact;
    if value.origin != 0 {
        fact = none;
        if m.node(node).tag == blot_check_core::Tag.reference {
            fact = self_.facts[value.origin];
        } else if m.node(node).tag == blot_check_core::Tag.project && local(self_, value.origin) && self_.function_roots.len != 0 && self_.home[value.origin] == self_.function_roots[self_.function_roots.len - 1] {
            // A field of a local of its own leaves with the function.
            let target, found = place(self_, m, node);
            if found && target.len != 0 && target.binding == value.origin { fact = partFact(self_, self_.facts[value.origin], target.fields[..target.len]); }
            if fact == spent { fact = none; }
        }
    }
    if !owns(self_, m, m.typeOf(node)) { return; }
    if !ownedAs(self_, m, fact, m.typeOf(node), 0) { reject(self_, m, culprit(self_, m, node), blot_check_core::Code.result_not_owned); }
}
// Whether the function or closure with `root` must return a value nothing
// else holds: one that takes over a parameter, and under the rules being
// measured every one whose result can own an array.
fn resultChecked(self_: Analyzer&, m: const Module&, root: u32, ty: u32) -> bool {
    if root == self_.owned_result { return owns(self_, m, ty); }
    if root == self_.exempt_root { return false; }
    return owns(self_, m, ty);
}
// Whether a value of `ty` with `fact` is unique all the way down. A record
// fact is when every field that holds storage is; a nominal is read through
// its one record constructor when it has no type parameters.
recursive fn ownedAs(self_: Analyzer&, m: const Module&, fact: Fact, ty: u32, depth: i64) -> bool {
    if fact == deep { return true; }
    if !holds(self_, m, ty) { return true; }
    // A part that only borrows may hold what it likes, and so may the
    // elements of an array that is itself unique.
    if !owns(self_, m, ty) { return true; }
    if fact == shell {
        let inner = element(self_, m, ty);
        if inner.present && !owns(self_, m, inner.value) { return true; }
    }
    if fact < first_record || fact >= spent || depth > 16 || ty >= m.types.nodes.len { return false; }
    var shape = m.types.node(ty);
    if shape.tag == blot_check_types::Tag.nominal {
        if blot_check_storage_types::identity(shape.a, shape.b).present || shape.a == 0xffffffff { return false; }
        let index, found = nominalIndex(self_, m, shape.a, shape.b);
        if !found { return false; }
        let nominal = m.nominal(index);
        let constructors = m.nominalConstructors(index);
        if nominal.is_opaque || nominal.variables.len != 0 || constructors.len == 0 { return false; }
        // Whichever constructor made the value, each field of its that
        // can own an array has the fact its name has.
        for constructor in constructors {
            let payload = m.constructor(constructor).payload;
            if payload == 0 { continue; }
            if payload >= m.types.nodes.len { return false; }
            let fields = m.types.node(payload);
            if fields.tag != blot_check_types::Tag.record { if owns(self_, m, payload) { return false; } continue; }
            for index in 0..fields.b {
                let declared = m.types.recordField(fields, index);
                if !ownedAs(self_, m, field(self_, fact, declared.name), declared.ty, depth + 1) { return false; }
            }
        }
        return true;
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
// The statements of a block or a suite, one after another. Each is the
// place where the loans of names it read for the last time end, and the
// result of a call that stands as a statement is gone with it.
recursive fn statements(self_: Analyzer&, m: const Module&, id: u32) -> bool {
    var exits = false;
    let mark = self_.loans.len;
    let outer_mark = self_.statement_mark;
    let outer_loops = self_.statement_loops;
    let outer_roots = self_.statement_roots;
    let outer_tentative = self_.statement_tentative;
    for child in m.children(id) {
        self_.statement_mark = mark;
        self_.statement_loops = self_.loops.len;
        self_.statement_roots = self_.function_roots.len;
        self_.statement_tentative = self_.tentative;
        let discarded = m.node(child).tag == blot_check_core::Tag.call || m.node(child).tag == blot_check_core::Tag.apply;
        let ends = self_.briefs.len;
        if discarded { self_.brief_node = child; }
        let value = visit(self_, m, child);
        self_.brief_node = 0;
        if discarded { endBriefs(self_, ends); }
        exits = value.exits || exits;
        giveBackLoans(self_, mark, false);
    }
    giveBackLoans(self_, mark, true);
    self_.statement_mark = outer_mark;
    self_.statement_loops = outer_loops;
    self_.statement_roots = outer_roots;
    self_.statement_tentative = outer_tentative;
    return exits;
}
recursive fn block_(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    self_.blocks.push(BlockFrame { id: id, .. });
    let exits = statements(self_, m, id);
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
    let leaving = id == self_.result_node;
    for child, index in m.children(id) {
        if leaving { self_.result_node = child; }
        let value = visit(self_, m, child);
        var fact: Fact = none;
        if leaving { fact = takenPart(self_, m, child, value); } else { fact = taken(self_, m, child, value); }
        exits = exits || value.exits;
        if !self_.dry && !self_.culprits.contains(id) && owns(self_, m, m.typeOf(child)) && !ownedAs(self_, m, fact, m.typeOf(child), 0) { self_.culprits.insert(id, child); }
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
    self_.base_node = info.root;
    let root = visit(self_, m, info.root);
    self_.base_node = 0;
    for step in selectors { if step.kind == blot_check_core::UpdateKind.index { visitEscaping(self_, m, step.index); } }
    // `self` in the value is the old leaf, which this update replaces: it
    // is unique when every array the path goes through is, and a value
    // read out of an array is only when the array is unique all the way
    // down. So `world.items := grown self x` can give the old leaf away.
    if !info.store && info.self_binding != 0 && local(self_, info.self_binding) {
        var leaf: Fact = none;
        if local(self_, root.origin) && self_.facts[root.origin] != spent {
            leaf = self_.facts[root.origin];
            for step in selectors {
                if step.kind == blot_check_core::UpdateKind.field { leaf = field(self_, leaf, m.projection(step.projection).field); } else if leaf != deep { leaf = none; }
            }
            if selectors.len == 0 { for projection in m.updatePath(id) { leaf = field(self_, leaf, m.projection(projection).field); } }
        }
        define(self_, info.self_binding, leaf);
        if self_.in_fork != 0 { setForkTaint(self_, info.self_binding, nodeTaint(self_, m, info.root, 0)); }
    }
    let value = visit(self_, m, info.value);
    let replacement = taken(self_, m, info.value, value);
    var through_storage = false;
    for step in selectors { through_storage = through_storage || step.kind == blot_check_core::UpdateKind.index; }
    var leaf = m.typeOf(info.value);
    if selectors.len != 0 { leaf = selectors[selectors.len - 1].result_type; }
    let shared = holds(self_, m, leaf) && replacement != deep;
    if info.store {
        if self_.report_stores && through_storage && local(self_, root.origin) && accepts(self_, m, self_.facts[root.origin], selectors) { reject(self_, m, id, blot_check_core::Code.unchecked); }
        // A store through what the function was lent keeps the value there,
        // so the arrays the value owns must be nobody else's.
        if shared && !keeping(self_) && !(local(self_, root.origin) && accepts(self_, m, self_.facts[root.origin], selectors)) && (!ownedAs(self_, m, replacement, m.typeOf(info.value), 0) || lentHolder(self_, m, info.value)) { reject(self_, m, id, blot_check_core::Code.kept_value); }
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
        var first: u32 = 0;
        if self_.fields.len > mark { first = self_.fields[mark]; }
        self_.fields.resize(mark);
        define(self_, successor, replaced);
        if self_.in_fork != 0 && local(self_, successor) { setForkTaint(self_, successor, maxU32(nodeTaint(self_, m, info.root, 0), nodeTaint(self_, m, info.value, 0))); }
        moveLoans(self_, root.origin, successor, first);
        return Value { exits: value.exits, .. };
    }
    if !accepts(self_, m, old, selectors) || (self_.in_fork != 0 && local(self_, root.origin) && self_.function_roots.len != 0 && self_.home[root.origin] != self_.function_roots[self_.function_roots.len - 1]) { reject(self_, m, id, blot_check_core::Code.aliased_update); }
    for step in selectors {
        if step.kind == blot_check_core::UpdateKind.index { break; }
        self_.fields.push(m.projection(step.projection).field);
    }
    var next = old;
    if shared { next = weaken(self_, old, self_.fields[mark..]); }
    var through: u32 = 0;
    if self_.fields.len > mark { through = self_.fields[mark]; }
    self_.fields.resize(mark);
    define(self_, successor, next);
    if self_.in_fork != 0 && local(self_, successor) { setForkTaint(self_, successor, maxU32(nodeTaint(self_, m, info.root, 0), nodeTaint(self_, m, info.value, 0))); }
    moveLoans(self_, root.origin, successor, through);
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
recursive fn arrayOp(self_: Analyzer&, m: const Module&, id: u32, bound: bool, brief: bool, lends_to: u32) -> Value {
    let n = m.node(id);
    let children = m.children(id);
    let operation = m.arrayOperation(id);
    if operation == blot_backend_collection_ops::Op.length {
        let container = receiver(self_, m, children[0], 0, false, 0);
        return Value { exits: container.exits, .. };
    }
    if operation == blot_backend_collection_ops::Op.get || operation == blot_backend_collection_ops::Op.simd_load {
        var element = n.ty;
        if operation != blot_backend_collection_ops::Op.get { element = 0; }
        let container = receiver(self_, m, children[0], element, brief, lends_to);
        let index = visitEscaping(self_, m, children[1]);
        let exits = container.exits || index.exits;
        if operation == blot_backend_collection_ops::Op.get && holds(self_, m, n.ty) { return Value { origin: container.origin, exits: exits, .. }; }
        return Value { exits: exits, .. };
    }
    if operation == blot_backend_collection_ops::Op.identity { return visit(self_, m, children[0]); }
    if operation == blot_backend_collection_ops::Op.simd_store {
        // Writes four elements in place and returns the same storage. On
        // storage the function does not own that is a store like `=`: the
        // result is the same shared storage. It needs an owner when `=` goes.
        let container = visit(self_, m, children[0]);
        let fresh = container.origin == 0 && unique(container.fact);
        for child in children[1..] { visitEscaping(self_, m, child); }
        if fresh { return Value { fact: container.fact, exits: container.exits, .. }; }
        // A local written at its last read hands its storage on.
        if container.origin != 0 && moves(self_, m, children[0], container.origin) {
            let fact = self_.facts[container.origin];
            kill(self_, container.origin);
            return Value { fact: fact, exits: container.exits, .. };
        }
        return Value { origin: container.origin, exits: container.exits, .. };
    }
    if bound && operation == blot_backend_collection_ops::Op.append && children.len == 2 && m.node(children[0]).tag == blot_check_core::Tag.reference {
        // The backend grows an input named once in place, so the result is
        // that input's storage with one more element. A module without
        // stores may only do that to an array it owns.
        let grown = visit(self_, m, children[0]);
        let owned = local(self_, grown.origin) && unique(self_.facts[grown.origin]);
        let item = visit(self_, m, children[1]);
        let added = taken(self_, m, children[1], item);
        let exits = grown.exits || item.exits;
        if owned {
            var fact = self_.facts[grown.origin];
            if fact == deep && elementHolds(self_, m, n.ty) && !ownedAs(self_, m, added, m.typeOf(children[1]), 0) { fact = shell; }
            kill(self_, grown.origin);
            return Value { fact: fact, exits: exits, .. };
        }
        reject(self_, m, id, blot_check_core::Code.aliased_update);
        escape(self_, grown);
        return Value { exits: exits, .. };
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
        if operation == blot_check_storage_ops::Op.view {
            // A view borrows the storage it names, as a value read out of
            // it does: it is given back where the view is last used.
            let container = visit(self_, m, children[0]);
            var exits = container.exits;
            for child in children[1..] { let value = visitEscaping(self_, m, child); exits = value.exits || exits; }
            return Value { origin: container.origin, exits: exits, .. };
        }
        if operation == blot_check_storage_ops::Op.push {
            let container = visit(self_, m, children[0]);
            let value = visit(self_, m, children[1]);
            let pushed = taken(self_, m, children[1], value);
            // A push into storage the function was lent is a store like
            // `=` (until that goes). It may put there only a value it
            // owns, or the caller would go on updating in place what the
            // storage now holds.
            if !keeping(self_) && !storageOwned(self_, m, children[0]) && (!ownedAs(self_, m, pushed, m.typeOf(children[1]), 0) || lentHolder(self_, m, children[1])) { reject(self_, m, id, blot_check_core::Code.kept_value); }
            if elementHolds(self_, m, m.typeOf(children[0])) && pushed != deep && !ownedAs(self_, m, pushed, m.typeOf(children[1]), 0) { sharedInto(self_, m, children[0], []); }
            return Value { exits: container.exits || value.exits, .. };
        }
        if operation == blot_check_storage_ops::Op.copy {
            let input_ty = m.typeOf(children[0]);
            let container = visit(self_, m, children[0]);
            if !blot_check_storage_types::isShared(m.types, input_ty) && blot_check_storage_types::arrayElement(m.types, n.ty).present && elementHolds(self_, m, n.ty) { escape(self_, container); }
            if blot_check_storage_types::arrayElement(m.types, n.ty).present {
                let fact = freshContainer(self_, m, n.ty, blot_check_storage_types::isShared(m.types, input_ty));
                return Value { fact: fact, exits: container.exits, .. };
            }
            return Value { fact: deep, exits: container.exits, .. };
        }
        if operation == blot_check_storage_ops::Op.share {
            // `freeze x`: takes over a linear value in O(1) and produces `*T`,
            // or freezes a closure/partial application into `*(A -> B)` (2B)
            // provided all captures are inline or `*T` (no linear/borrowed captures).
            let child = children[0];
            let input_ty = m.typeOf(child);
            if m.types.node(input_ty).tag == blot_check_types::Tag.function {
                let container = visit(self_, m, child);
                if closureNonFreezable(self_, m, child) { reject(self_, m, child, blot_check_core::Code.own_function_value); }
                return Value { fact: none, exits: container.exits, .. };
            }
            if blot_check_storage_types::isShared(m.types, input_ty) || !holds(self_, m, input_ty) {
                let container = visit(self_, m, child);
                return Value { fact: none, exits: container.exits, .. };
            }
            var named: u32 = 0;
            if m.node(child).tag == blot_check_core::Tag.reference {
                let target = m.reference(child);
                if (target.unit == 0 || target.unit == m.unit) && local(self_, target.binding) { named = target.binding; }
            }
            var part = Place { .. };
            if named == 0 {
                let target, found = place(self_, m, child);
                if found && target.len != 0 && local(self_, target.binding) { part = target; }
            }
            var was_spent = named != 0 && self_.facts[named] == spent;
            if part.len != 0 && partFact(self_, self_.facts[part.binding], part.fields[..part.len]) == spent { was_spent = true; }
            let value = visit(self_, m, child);
            if was_spent { return Value { fact: none, exits: value.exits, .. }; }
            var accepted = false;
            var loop_id: u32 = 0;
            if self_.loops.len != 0 { loop_id = self_.loops[self_.loops.len - 1].id; }
            if value.origin == 0 {
                accepted = ownedAs(self_, m, value.fact, input_ty, 0);
            } else if named != 0 {
                accepted = self_.born[named] == loop_id && ownedAs(self_, m, self_.facts[named], input_ty, 0);
            } else if part.len != 0 && value.origin == part.binding {
                let fact = partFact(self_, self_.facts[part.binding], part.fields[..part.len]);
                accepted = self_.born[part.binding] == loop_id && fact != spent && ownedAs(self_, m, fact, input_ty, 0);
            }
            if !accepted { reject(self_, m, child, blot_check_core::Code.own_argument); }
            if accepted && named != 0 {
                set(self_, named, spent);
            } else if accepted && part.len != 0 && value.origin == part.binding {
                let given = replace(self_, self_.facts[part.binding], part.fields[..part.len], spent);
                set(self_, part.binding, given);
            } else {
                escape(self_, value);
            }
            return Value { fact: none, exits: value.exits, .. };
        }
        if operation == blot_check_storage_ops::Op.freeze {
            let container = visit(self_, m, children[0]);
            // Freezing a local at its last read gives its storage away.
            if container.origin != 0 && moves(self_, m, children[0], container.origin) {
                let fact = self_.facts[container.origin];
                kill(self_, container.origin);
                return Value { fact: fact, exits: container.exits, .. };
            }
            // A fresh value frozen is still that fresh value.
            if container.origin == 0 { return Value { fact: container.fact, exits: container.exits, .. }; }
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
    self_.tentative += 1;
    var first = visit(self_, m, n.b);
    if n.tag == blot_check_core::Tag.if_value { first = armValue(self_, m, n.b, first); }
    arm(self_, join, 0, first);
    var second = Value { .. };
    if n.c != 0 { second = visit(self_, m, n.c); }
    if n.tag == blot_check_core::Tag.if_value { second = armValue(self_, m, n.c, second); }
    arm(self_, join, 1, second);
    self_.tentative -= 1;
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
    self_.tentative += 1;
    for case_, index in m.matchArms(id) {
        var guard_exits = false;
        if case_.guard_ != 0 { let guarded = visitEscaping(self_, m, case_.guard_); guard_exits = guarded.exits; }
        var body = Value { .. };
        if case_.body != 0 { body = visit(self_, m, case_.body); }
        body = armValue(self_, m, case_.body, body);
        body.exits = body.exits || guard_exits;
        arm(self_, join, index, body);
    }
    self_.tentative -= 1;
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
    var aliasing = false;
    let ends = self_.briefs.len;
    if info.kind == blot_check_core::LoopKind.range {
        let first = visitEscaping(self_, m, info.first);
        exits = first.exits || exits;
        let end = visitEscaping(self_, m, info.end);
        exits = end.exits || exits;
    } else if info.kind == blot_check_core::LoopKind.array {
        // The pattern binds elements, so storage-holding ones alias. The
        // loop reads its source throughout, so a carry that starts as the
        // source is observed by every iteration.
        // What the loop walks is shared for the loop, and so is what a
        // call borrowed to make it. Both are given back after the loop,
        // unless an element that holds storage may have left it (below).
        aliasing = elementHolds(self_, m, m.typeOf(info.first));
        self_.brief_node = info.first;
        let source = visit(self_, m, info.first);
        self_.brief_node = 0;
        exits = source.exits;
        if !aliasing {
            iterated = source.origin;
        } else if local(self_, source.origin) && self_.facts[source.origin] != spent {
            let fact = self_.facts[source.origin];
            set(self_, source.origin, none);
            self_.briefs.push(Captured { binding: source.origin, fact: fact, stamp: self_.touch[source.origin] });
        } else {
            escape(self_, source);
        }
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
    // An element can leave the loop only in a carry, and a carry that is
    // its own all the way down holds none.
    var kept = false;
    for carry, at in carries {
        let met = meet(self_, self_.loop_facts[assumed + at], self_.loop_facts[outgoing + at]);
        define(self_, carry.outgoing, met);
        if self_.in_fork != 0 {
            let ct = maxU32(getForkTaint(self_, carry.incoming), getForkTaint(self_, carry.backedge));
            if ct != 0 { setForkTaint(self_, carry.outgoing, maxU32(getForkTaint(self_, carry.outgoing), ct)); }
        }
        if aliasing && carry.outgoing < m.bindings.len {
            let ty = m.bindings[carry.outgoing].ty;
            if holds(self_, m, ty) && !ownedAs(self_, m, met, ty, 0) { kept = true; }
        }
    }
    self_.loop_facts.resize(incoming);
    if kept {
        for at in ends..self_.briefs.len { kill(self_, self_.briefs[at].binding); }
        self_.briefs.resize(ends);
    }
    endBriefs(self_, ends);
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
    for carry, at in carries {
        define(self_, carry.iteration, self_.loop_facts[assumed + at]);
        if self_.in_fork != 0 {
            let ct = maxU32(getForkTaint(self_, carry.incoming), getForkTaint(self_, carry.backedge));
            if ct != 0 { setForkTaint(self_, carry.iteration, maxU32(getForkTaint(self_, carry.iteration), ct)); }
        }
    }
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
        if self_.in_fork != 0 && n.op != blot_check_core::Op.continue_ {
            let taint = nodeTaint(self_, m, child, 0);
            if taint != 0 {
                let loop_carries = m.loopCarries(n.a);
                if position < loop_carries.len { setForkTaint(self_, loop_carries[position].outgoing, maxU32(getForkTaint(self_, loop_carries[position].outgoing), taint)); }
            }
        }
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
        if self_.in_fork != 0 {
            let mt = maxU32(getForkTaint(self_, merge.then_binding), getForkTaint(self_, merge.else_binding));
            if mt != 0 { setForkTaint(self_, merge.result, mt); }
        }
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

// ---- Speculative fork & 2B frozen closures -----------------------------

fn maxU32(a: u32, b: u32) -> u32 { if a >= b { return a; } return b; }
fn setForkTaint(self_: Analyzer&, binding: u32, taint: u32) {
    if local(self_, binding) { self_.fork_taint[binding] = taint; }
}
fn getForkTaint(self_: const Analyzer&, binding: u32) -> u32 {
    if !local(self_, binding) { return 0; }
    return self_.fork_taint[binding];
}
fn markBlockTaint(self_: Analyzer&, block_id: u32, taint: u32) {
    if taint == 0 { return; }
    let prev .= self_.block_taint.get(block_id);
    var merged = taint;
    if prev { let old: u32 = prev; merged = maxU32(old, taint); }
    self_.block_taint.insert(block_id, merged);
}
fn setNonFreezable(self_: Analyzer&, binding: u32, value: bool) {
    if local(self_, binding) { self_.non_freezable[binding] = value; }
}
fn isNonFreezable(self_: const Analyzer&, binding: u32) -> bool {
    return local(self_, binding) && self_.non_freezable[binding];
}
recursive fn taintPattern(self_: Analyzer&, m: const Module&, pattern: u32, taint: u32, depth: i64) {
    if pattern == 0 || pattern >= m.patterns.len || depth > 64 { return; }
    let shape = m.pattern(pattern);
    if shape.tag == blot_check_core::PatternTag.bind { setForkTaint(self_, shape.a, maxU32(getForkTaint(self_, shape.a), taint)); return; }
    if shape.tag == blot_check_core::PatternTag.product { for child in m.patternChildren(pattern) { taintPattern(self_, m, child, taint, depth + 1); } return; }
    if shape.tag == blot_check_core::PatternTag.constructor || shape.tag == blot_check_core::PatternTag.record_payload { taintPattern(self_, m, shape.b, taint, depth + 1); }
}
// Maximum fork depth whose shadowed storage `id` may alias (0 = untainted).
recursive fn nodeTaint(self_: Analyzer&, m: const Module&, id: u32, depth: i64) -> u32 {
    if id == 0 || id >= m.nodes.len || depth > 32 { return 0; }
    let n = m.node(id);
    if !holds(self_, m, n.ty) && !blot_check_storage_types::isShared(m.types, n.ty) { return 0; }
    if n.tag == blot_check_core::Tag.reference {
        let target = m.reference(id);
        if target.unit != 0 && target.unit != m.unit { return 0; }
        return getForkTaint(self_, target.binding);
    }
    if n.tag == blot_check_core::Tag.project {
        let _, is_copy = memberCopy(self_, m, id);
        if is_copy && !elementHolds(self_, m, n.ty) { return 0; }
        return nodeTaint(self_, m, n.a, depth + 1);
    }
    if n.tag == blot_check_core::Tag.storage {
        let children = m.children(id);
        if children.len == 0 { return 0; }
        let op, unknown = blot_check_storage_ops::opFromCode(n.c);
        if unknown == blot_error::Error.none && op == blot_check_storage_ops::Op.copy {
            if !blot_check_storage_types::arrayElement(m.types, n.ty).present || !elementHolds(self_, m, n.ty) { return 0; }
        }
        return nodeTaint(self_, m, children[0], depth + 1);
    }
    if n.tag == blot_check_core::Tag.array_op {
        let op = m.arrayOperation(id);
        let children = m.children(id);
        if op == blot_backend_collection_ops::Op.slice || op == blot_backend_collection_ops::Op.concat || op == blot_backend_collection_ops::Op.set || op == blot_backend_collection_ops::Op.convert || op == blot_backend_collection_ops::Op.prepend || op == blot_backend_collection_ops::Op.append || op == blot_backend_collection_ops::Op.flatten {
            if !elementHolds(self_, m, n.ty) { return 0; }
        }
        var best: u32 = 0;
        for child in children { best = maxU32(best, nodeTaint(self_, m, child, depth + 1)); }
        return best;
    }
    if n.tag == blot_check_core::Tag.call {
        var best: u32 = 0;
        for child in m.call(id).arguments { best = maxU32(best, nodeTaint(self_, m, child, depth + 1)); }
        return best;
    }
    if n.tag == blot_check_core::Tag.apply || n.tag == blot_check_core::Tag.record_merge {
        return maxU32(nodeTaint(self_, m, n.a, depth + 1), nodeTaint(self_, m, n.b, depth + 1));
    }
    if n.tag == blot_check_core::Tag.construct { return nodeTaint(self_, m, n.b, depth + 1); }
    if n.tag == blot_check_core::Tag.product || n.tag == blot_check_core::Tag.record || n.tag == blot_check_core::Tag.array {
        var best: u32 = 0;
        for child in m.children(id) { best = maxU32(best, nodeTaint(self_, m, child, depth + 1)); }
        return best;
    }
    if n.tag == blot_check_core::Tag.if_value {
        return maxU32(nodeTaint(self_, m, n.b, depth + 1), nodeTaint(self_, m, n.c, depth + 1));
    }
    if n.tag == blot_check_core::Tag.match_ {
        var best: u32 = 0;
        for case_ in m.matchArms(id) { best = maxU32(best, nodeTaint(self_, m, case_.body, depth + 1)); }
        return best;
    }
    if n.tag == blot_check_core::Tag.update {
        let info = m.updateInfo(id);
        return maxU32(nodeTaint(self_, m, info.root, depth + 1), nodeTaint(self_, m, info.value, depth + 1));
    }
    if n.tag == blot_check_core::Tag.block_ || n.tag == blot_check_core::Tag.fork_ {
        var key = id;
        if n.tag == blot_check_core::Tag.fork_ { key = n.a; }
        let found .= self_.block_taint.get(key);
        if found { let v: u32 = found; return v; }
        return 0;
    }
    if n.tag == blot_check_core::Tag.closure {
        var best: u32 = 0;
        for captured in m.closureCaptures(id) { best = maxU32(best, getForkTaint(self_, captured)); }
        return best;
    }
    return 0;
}
// Whether function expression `id` captures linear/borrowed storage or an
// unfrozen callable and therefore cannot be frozen into `*(A -> B)` (2B).
recursive fn closureNonFreezable(self_: Analyzer&, m: const Module&, id: u32) -> bool {
    if id == 0 || id >= m.nodes.len { return false; }
    let n = m.node(id);
    if n.tag == blot_check_core::Tag.closure {
        for binding in m.closureCaptures(id) {
            if binding == 0 || binding >= m.bindings.len { continue; }
            let cap_ty = m.bindings[binding].ty;
            if holds(self_, m, cap_ty) || openType(m, cap_ty, 0) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_core::Tag.call {
        if m.call(id).own != 0 { return true; }
        for arg in m.call(id).arguments {
            let arg_ty = m.typeOf(arg);
            if holds(self_, m, arg_ty) || openType(m, arg_ty, 0) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_core::Tag.apply {
        let arg_ty = m.typeOf(n.b);
        if holds(self_, m, arg_ty) || openType(m, arg_ty, 0) { return true; }
        return closureNonFreezable(self_, m, n.a);
    }
    if n.tag == blot_check_core::Tag.reference {
        let target = m.reference(id);
        if (target.unit == 0 || target.unit == m.unit) && local(self_, target.binding) {
            if isNonFreezable(self_, target.binding) { return true; }
            let b = m.bindings[target.binding];
            if b.kind == blot_reuse_principal_interface::Kind.parameter && !blot_check_storage_types::isShared(m.types, b.ty) && m.types.node(b.ty).tag == blot_check_types::Tag.function { return true; }
            return false;
        }
        let named = calleeBinding(self_, m, id);
        if named != 0 && m.bindings[named].capability_parameters.own != 0 { return true; }
        return false;
    }
    if n.tag == blot_check_core::Tag.project {
        if m.dispatchSignature(id) != 0 {
            let recv_ty = m.typeOf(n.a);
            if holds(self_, m, recv_ty) || openType(m, recv_ty, 0) { return true; }
        }
        return false;
    }
    if n.tag == blot_check_core::Tag.operation_value { return true; }
    if n.tag == blot_check_core::Tag.if_value {
        return closureNonFreezable(self_, m, n.b) || closureNonFreezable(self_, m, n.c);
    }
    if n.tag == blot_check_core::Tag.match_ {
        for case_ in m.matchArms(id) { if closureNonFreezable(self_, m, case_.body) { return true; } }
        return false;
    }
    return false;
}
recursive fn forkNode(self_: Analyzer&, m: const Module&, id: u32) -> Value {
    let n = m.node(id);
    let block_id = n.a;
    let entry_count = n.b as i64;
    let children = m.children(block_id);
    // Verify each forked outer variable is live and uniquely owned (not aliased).
    for at in 0..entry_count {
        let bind_node = m.node(children[at]);
        let outer_ref = bind_node.b;
        let target = m.reference(outer_ref);
        let is_local = (target.unit == 0 || target.unit == m.unit) && local(self_, target.binding);
        if is_local { read(self_, target.binding, outer_ref); }
        if !self_.dry {
            if is_local && self_.facts[target.binding] == spent {
                reject(self_, m, outer_ref, blot_check_core::Code.spent_value);
            } else if holds(self_, m, m.typeOf(outer_ref)) {
                if !is_local || !ownedAs(self_, m, self_.facts[target.binding], m.typeOf(outer_ref), 0) {
                    reject(self_, m, outer_ref, blot_check_core::Code.aliased_update);
                }
            }
        }
    }
    let mark = self_.trail.len;
    let loan_mark = self_.loans.len;
    let outer_owned = self_.owned_result;
    let outer_exempt = self_.exempt_root;
    let outer_keeps = self_.keeps_root;
    let outer_mark = self_.statement_mark;
    let outer_loops = self_.statement_loops;
    let outer_roots = self_.statement_roots;
    let outer_tentative = self_.statement_tentative;
    self_.owned_result = block_id;
    self_.exempt_root = 0;
    self_.keeps_root = 0;
    self_.in_fork += 1;
    let depth_level = self_.in_fork;
    self_.function_roots.push(block_id);
    self_.blocks.push(BlockFrame { id: block_id, .. });
    for at in 0..entry_count {
        let bind_node = m.node(children[at]);
        let inner = bind_node.a;
        define(self_, inner, deep);
        setForkTaint(self_, inner, depth_level);
    }
    for at in entry_count..children.len {
        let child = children[at];
        self_.statement_mark = loan_mark;
        self_.statement_loops = self_.loops.len;
        self_.statement_roots = self_.function_roots.len;
        self_.statement_tentative = self_.tentative;
        let discarded = m.node(child).tag == blot_check_core::Tag.call || m.node(child).tag == blot_check_core::Tag.apply;
        let ends = self_.briefs.len;
        if discarded { self_.brief_node = child; }
        let _ = visit(self_, m, child);
        self_.brief_node = 0;
        if discarded { endBriefs(self_, ends); }
        giveBackLoans(self_, loan_mark, false);
    }
    giveBackLoans(self_, loan_mark, true);
    self_.blocks.resize(self_.blocks.len - 1);
    self_.function_roots.resize(self_.function_roots.len - 1);
    self_.in_fork -= 1;
    self_.owned_result = outer_owned;
    self_.exempt_root = outer_exempt;
    self_.keeps_root = outer_keeps;
    self_.statement_mark = outer_mark;
    self_.statement_loops = outer_loops;
    self_.statement_roots = outer_roots;
    self_.statement_tentative = outer_tentative;
    undo(self_, mark);
    var fact: Fact = none;
    if holds(self_, m, n.ty) { fact = deep; }
    return Value { fact: fact, .. };
}
