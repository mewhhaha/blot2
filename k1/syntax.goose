// Isolated owned syntax-structure experiment. No source grammar, completion,
// semantic safety or durable artifact authority is established by this model.
namespace syntax;
import lexer;
import work;

// Node tags: root 0, ordinary 1, function 2, value block 3, non-carry loop 4,
// carry loop 5, owned body 6, return 7, valued break 8, bare break 9,
// continue 10, next 11, stop 12, seal 13, abort 14. IDs are one-based;
// parent=0 is reserved for the root; target/reference=0 means absent.
// Optional references are earlier-node links: their permitted roles and
// source semantics remain outside this structural model.
struct Node {
    tag: i64 = 0, start: i64 = 0, end: i64 = 0,
    parent: i64 = 0, target: i64 = 0, reference: i64 = 0
}
struct Arena {
    source: u8[] = [], nodes: Node[] = []
}
struct Context {
    function: i64 = 0, value: i64 = 0, loop_target: i64 = 0, owned: i64 = 0
}

// The caller owns the resulting arrays and they retain no references into the
// supplied buffers. This isolated single-declaration experiment cannot have
// more nodes than the semantic visit ceiling, since each node consumes at
// least one visit. This is not a per-module source acceptance limit.
fn own(source: u8[:], nodes: Node[:]) -> Arena, bool {
    if source.len > 16777216 || nodes.len > 1048576 { return Arena {}, false; }
    return Arena { source: source, nodes: nodes }, true;
}

// 0 structurally valid; 1 malformed; 2 source/prototype semantic budget reached.
// This single-declaration experiment charges node and edge visits against
// K1-SEM-POLICY-1; it is not a complete admission or shared work receipt.
// All child
// references point strictly to earlier parents; source spans are contained in
// their parent. A control target is the appropriate nearest ancestor and may
// never cross a function boundary. Source spelling, suite shape, nested syntax
// depth, token/UTF-8 boundaries, child ordering, legal parent kinds, ownership
// and reachability require separate checks.
struct ValidationWork { visits: i64 = 0, budget: i64 = 1048576, enabled: bool = false, phase: u32 = 2, failure: i64 = 0 }

// A structural node/edge is not visited until its charge succeeds. The local
// prototype budget is retained for the compatibility API; a metered call
// additionally spends from its caller's declaration-owned meter.
fn visit(v: ValidationWork&, meter: work::Meter&, event: u32) -> bool {
    if v.visits >= v.budget { v.failure = if v.enabled { 3 } else { 2 }; return false; }
    if v.enabled {
        let receipt = work::charge(meter, v.phase, event);
        if receipt.status != 0 {
            v.failure = if receipt.status == 1 { 3 } else { 4 };
            return false;
        }
    }
    v.visits += 1;
    return true;
}

fn validate(arena: Arena&) -> i64 { return validate_budget(arena, 1048576); }
fn validate_budget(arena: Arena&, budget: i64) -> i64 {
    var meter = work::Meter {};
    var visits = ValidationWork { budget: budget };
    return validate_impl(arena, visits, meter);
}

// 0 valid, 1 malformed, 2 local prototype/source limit, 3 shared semantic
// limit, 4 invalid accounting state. Raw source-byte telemetry is not yet
// instrumented and this does not establish a complete K1 work receipt.
fn validate_with_work(arena: Arena&, meter: work::Meter&, phase: u32) -> i64 {
    if phase != 2 && phase != 5 { return 4; }
    var visits = ValidationWork { enabled: true, phase: phase };
    return validate_impl(arena, visits, meter);
}

fn validate_impl(arena: Arena&, visits: ValidationWork&, meter: work::Meter&) -> i64 {
    let budget = visits.budget;
    if budget < 0 || budget > 1048576 { return 1; }
    if arena.source.len > 16777216 { return 2; }
    if arena.nodes.len > 1048576 { return if visits.enabled { 3 } else { 2 }; }
    if lexer::invalid_utf8(arena.source) >= 0 || arena.nodes.len == 0 { return 1; }
    if !visit(visits, meter, 2) { return visits.failure; } // root node
    let root = arena.nodes[0];
    if root.tag != 0 || root.parent != 0 || root.target != 0 || root.reference != 0 ||
       root.start != 0 || root.end != arena.source.len { return 1; }
    var contexts: Context[>..] = [];
    contexts.push(Context {});
    for i in 1..arena.nodes.len {
        if !visit(visits, meter, 2) { return visits.failure; } // node
        let n = arena.nodes[i];
        if n.tag < 1 || n.tag > 14 || n.start < 0 || n.end < n.start || n.end > arena.source.len { return 1; }
        // Retain the historical compatibility API's malformed-before-budget
        // result. The opt-in path charges each represented edge before
        // validating or following that edge.
        if !visits.enabled && (n.parent < 1 || n.parent > i || n.reference < 0 || n.reference > i) { return 1; }
        if !visit(visits, meter, 3) { return visits.failure; } // parent edge
        if n.parent < 1 || n.parent > i { return 1; }
        let parent = arena.nodes[n.parent - 1];
        if n.start < parent.start || n.end > parent.end { return 1; }
        var ctx = contexts[n.parent - 1];
        let id = i + 1;
        if n.reference != 0 {
            if !visit(visits, meter, 3) { return visits.failure; } // reference edge
            if n.reference < 0 || n.reference > i { return 1; }
        }
        if n.tag >= 7 {
            if !visit(visits, meter, 3) { return visits.failure; } // target edge
        }
        var expected: i64 = 0;
        if n.tag == 7 { expected = ctx.function; }
        else if n.tag == 8 { expected = ctx.value; }
        else if n.tag == 9 || n.tag == 10 {
            if ctx.loop_target != 0 {
                if !visit(visits, meter, 2) { return visits.failure; } // loop-kind lookup
                if arena.nodes[ctx.loop_target - 1].tag == 4 { expected = ctx.loop_target; }
            }
        } else if n.tag == 11 || n.tag == 12 {
            if ctx.loop_target != 0 {
                if !visit(visits, meter, 2) { return visits.failure; } // loop-kind lookup
                if arena.nodes[ctx.loop_target - 1].tag == 5 { expected = ctx.loop_target; }
            }
        } else if n.tag == 13 || n.tag == 14 { expected = ctx.owned; }
        if n.tag >= 7 {
            if expected == 0 || n.target != expected { return 1; }
            // No control transfer may escape an active owned construction.
            // Ancestor IDs increase down this tree, so a target before the
            // current owned node is outside its subtree.
            if n.tag <= 12 && ctx.owned != 0 && expected < ctx.owned { return 1; }
        } else if n.target != 0 { return 1; }
        if n.tag == 2 { ctx = Context { function: id }; }
        else if n.tag == 3 { ctx.value = id; }
        else if n.tag == 4 || n.tag == 5 { ctx.loop_target = id; }
        else if n.tag == 6 { ctx.owned = id; }
        contexts.push(ctx);
    }
    return 0;
}
