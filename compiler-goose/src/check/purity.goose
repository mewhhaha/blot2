// Context-sensitive relational storage-graph purity analyzer (`checkReadOnlyFootprint`).
// Implements tasks/CONCURRENCY_VNEXT.md §2.5 verbatim using flat Goose pools and
// zero resizable locals in recursive functions (§7.8).
namespace blot_check_purity;

import std;
import dictionary;
import check.core;
import check.effects;
import check.types;
import check.storage_ops;
import check.storage_types;
import check.diagnostic_code;
import check.wire_schema;
import backend.collection_ops;
import reuse.principal_interface;
import support.error;
import support.option;

type Module = blot_check_core::Module;
type BindingRef = blot_check_core::BindingRef;
type TId = blot_check_types::Id;
type Identity = blot_check_types::NominalIdentity;
type Code = blot_check_diagnostic_code::Code;
type Chars = const u8[:];

// Hard polynomial bounds (§2.5).
let K_CALL_DEPTH: i64 = 3;
let MAX_PATHS_PER_SITE: i64 = 16;
let MAX_CONTEXTS_PER_FN: i64 = 16;
let MAX_HANDLER_DEPTH: i64 = 8;

// Edge labels (§2.5).
let LBL_ANY: u32 = 0;
let LBL_ELEM: u32 = 1;
let LBL_CTOR_PAYLOAD: u32 = 2;
let LBL_TUPLE_BASE: u32 = 16;
let LBL_CAPTURE_BASE: u32 = 4112;
let LBL_FIELD_BASE: u32 = 8208;

// Symbolic node kinds (§2.5).
let SYM_EMPTY_ENV: u8 = 0;
let SYM_PARAM: u8 = 1;
let SYM_CAPTURE: u8 = 2;
let SYM_GLOBAL: u8 = 3;
let SYM_CHILD: u8 = 4;
let SYM_PARAM_ENV: u8 = 5;
let SYM_CAP_NODE: u8 = 6;
let SYM_HANDLER_CAP: u8 = 7;
let SYM_HANDLER_CELL: u8 = 8;
let SYM_FRESH: u8 = 9;
let SYM_CALLEE_FRESH: u8 = 10;
let SYM_SUM_ALLOC: u8 = 11;
let SYM_FN_VAL: u8 = 12;
let SYM_SUM_FN: u8 = 13;
let SYM_OP_VAL: u8 = 14;
let SYM_CTOR_FN: u8 = 15;
let SYM_PRIM_FN: u8 = 16;

// Bounded call paths.
let PATH_EMPTY: u32 = 0;
let PATH_WILDCARD: u32 = 1;

struct SymKey {
    kind: u8 = 0,
    sub: u8 = 0,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
}
fn hash(k: SymKey) -> u64 {
    let h1 = ::hash_combine(::hash(k.kind as u32), ::hash(k.sub as u32));
    let h2 = ::hash_combine(::hash(k.a), ::hash(k.b));
    return ::hash_combine(::hash_combine(h1, h2), ::hash(k.c));
}

struct Edge {
    src: u32 = 0,
    lbl: u32 = 0,
    dst: u32 = 0,
}
fn hash(e: Edge) -> u64 {
    return ::hash_combine(::hash_combine(::hash(e.src), ::hash(e.lbl)), ::hash(e.dst));
}

struct CtxEdgeKey {
    ctx_id: u32 = 0,
    src: u32 = 0,
    lbl: u32 = 0,
    dst: u32 = 0,
}
fn hash(k: CtxEdgeKey) -> u64 {
    let h1 = ::hash_combine(::hash(k.ctx_id), ::hash(k.src));
    let h2 = ::hash_combine(::hash(k.lbl), ::hash(k.dst));
    return ::hash_combine(h1, h2);
}

struct PathKey {
    len: u8 = 0,
    c0: u32 = 0,
    c1: u32 = 0,
    c2: u32 = 0,
}
fn hash(p: PathKey) -> u64 {
    let h1 = ::hash_combine(::hash(p.len as u32), ::hash(p.c0));
    let h2 = ::hash_combine(::hash(p.c1), ::hash(p.c2));
    return ::hash_combine(h1, h2);
}

struct SiteKey {
    unit: u32 = 0,
    node: u32 = 0,
    sub: u32 = 0,
}
fn hash(s: SiteKey) -> u64 {
    return ::hash_combine(::hash_combine(::hash(s.unit), ::hash(s.node)), ::hash(s.sub));
}

struct CallSiteInfo {
    enclosing_fn: u32 = 0,
    unit: u32 = 0,
    node: u32 = 0,
}

struct OpKeyData {
    identity: Identity = Identity { 0, 0 },
    instance: Identity = Identity { 0, 0 },
}
fn hash(k: OpKeyData) -> u64 {
    let h1 = ::hash_combine(::hash(k.identity.unit), ::hash(k.identity.decl));
    let h2 = ::hash_combine(::hash(k.instance.unit), ::hash(k.instance.decl));
    return ::hash_combine(h1, h2);
}

struct Range {
    start: i64 = 0,
    len: i64 = 0,
}

struct NormUpdateStep {
    is_index: bool = false,
    field_lbl: u32 = 0,
    index_node: u32 = 0,
}

struct WithEntry {
    outer_b: u32 = 0,
    after_b: u32 = 0,
    cell_sym: u32 = 0,
    saved_cell: u32 = 0,
    saved_had: bool = false,
}

// Flat linked-list pool nodes (index 0 is sentinel / empty).
struct U32Node { val: u32 = 0, next: u32 = 0 }
struct EdgeNode { edge: Edge = Edge {}, next: u32 = 0, next_src: u32 = 0 }
struct CallerNode { caller_ctx: u32 = 0, call_site: u32 = 0, next: u32 = 0 }

struct AssocEntry {
    identity: Identity = Identity { 0, 0 },
    op: blot_check_types::Operator = blot_check_types::Operator.none,
    target: BindingRef = BindingRef { 0, 0 },
    next: u32 = 0,
}

struct ImplMemEntry {
    contract: Identity = Identity { 0, 0 },
    has_head_id: bool = false,
    is_prim_head: bool = false,
    head_id: Identity = Identity { 0, 0 },
    name_lbl: u32 = 0,
    target: BindingRef = BindingRef { 0, 0 },
    next_by_name: u32 = 0,
    next_by_contract: u32 = 0,
}

// Callable definitions across all units.
let FN_BODY: u8 = 0;
let FN_CLOSURE: u8 = 1;
let FN_SPARK: u8 = 2;

struct FnDef {
    kind: u8 = 0,
    unit: u32 = 0,
    binding: u32 = 0,
    node_id: u32 = 0,
    root: u32 = 0,
    is_function: bool = false,
    param_start: u32 = 0,
    param_len: u32 = 0,
    capture_start: u32 = 0,
    capture_len: u32 = 0,
    span: blot_check_core::Span = blot_check_core::Span { start: 0, end: 0 },
}

// Context specialization metadata for `FnCtx`.
struct CallableSpec {
    slot: u32 = 0,      // 0..999 = param j, 1000+i = capture i
    tag_kind: u8 = 0,   // 0 = FnVal, 1 = OpVal, 2 = CtorFn, 3 = PrimFn
    applied: u8 = 0,
    target_a: u32 = 0,  // fn_id / op_key_id / ctor_unit
    target_b: u32 = 0,  // 0 / 0 / ctor_idx
}

let HANDLER_CLOSURE: u8 = 0;
let HANDLER_STATE_GET: u8 = 1;
let HANDLER_STATE_SET: u8 = 2;

struct HandlerSpec {
    op_key: u32 = 0,
    kind: u8 = 0,
    fn_id: u32 = 0,
    applied: u8 = 0,
    cap_count: u16 = 0,
}

struct ActiveHandlerFrame {
    op_key: u32 = 0,
    kind: u8 = 0,
    fn_id: u32 = 0,
    applied: u8 = 0,
    env_sym: u32 = 0,
    cell_sym: u32 = 0,
    has_cell: bool = false,
    cap_count: u16 = 0,
}

struct SparkCheck {
    unit: u32 = 0,
    spark_node: u32 = 0,
    enclosing_ctx: u32 = 0,
    spark_ctx: u32 = 0,
    is_range: bool = false,
    src_head: u32 = 0,
    cap_start: u32 = 0,
    cap_len: u32 = 0,
    span: blot_check_core::Span = blot_check_core::Span { start: 0, end: 0 },
}

struct FnCtx {
    fn_id: u32 = 0,
    cspec_start: u32 = 0,
    cspec_len: u32 = 0,
    hspec_start: u32 = 0,
    hspec_len: u32 = 0,
    // Separated base vs written edge linked-list heads (§2.5).
    base_edges_head: u32 = 0,
    written_edges_head: u32 = 0,
    // Linked-list heads for touched local bindings, ret_pts, mutated, reads_globals, callers.
    touched_bindings_head: u32 = 0,
    ret_pts_head: u32 = 0,
    mutated_head: u32 = 0,
    reads_globals_head: u32 = 0,
    callers_head: u32 = 0,
    // Converged Summary heads.
    sum_ret_head: u32 = 0,
    sum_edges_head: u32 = 0,
    sum_mut_head: u32 = 0,
    sum_reads_head: u32 = 0,
    unresolved_error: bool = false,
    error_unit: u32 = 0,
    error_span: blot_check_core::Span = blot_check_core::Span { start: 0, end: 0 },
    error_code: Code = blot_check_diagnostic_code::Code.purity_limit,
    error_msg: Chars = "",
    dirty: bool = true,
    analyzed: bool = false,
    next_same_fn: u32 = 0,
}

struct Issue {
    failed: bool = false,
    unit: u32 = 0,
    span: blot_check_core::Span = blot_check_core::Span { start: 0, end: 0 },
    code: Code = blot_check_diagnostic_code::Code.spark_mutates_capture,
    message: Chars = "",
}

struct Result {
    issue: Issue = Issue {},
    deeply_immutable_digest: u64 = 0,
}

root struct Analyzer {
    entry: u32 = 0,
    // Flat linked pools (element 0 is sentinel).
    u32_nodes: U32Node[>..] = [],
    edge_nodes: EdgeNode[>..] = [],
    caller_nodes: CallerNode[>..] = [],
    fn_bindings: u32[>..] = [],
    spark_cap_bindings: u32[>..] = [],
    ctx_cspecs: CallableSpec[>..] = [],
    ctx_hspecs: HandlerSpec[>..] = [],
    // §7.8 mark-and-truncate scratch pools for recursive functions.
    head_stack: u32[>..] = [],
    handler_stack: ActiveHandlerFrame[>..] = [],
    step_stack: NormUpdateStep[>..] = [],
    edge_stack: Edge[>..] = [],
    with_stack: WithEntry[>..] = [],
    target_stack: BindingRef[>..] = [],
    // Per-ctx maps keyed by `(ctx_id << 32) | key`.
    ctx_pre_existing: dictionary<u64, bool> = dictionary<u64, bool>{},
    ctx_cell_bindings: dictionary<u64, bool> = dictionary<u64, bool>{},
    ctx_widened_sites: dictionary<u64, bool> = dictionary<u64, bool>{},
    ctx_binding_pts: dictionary<u64, u32> = dictionary<u64, u32>{},
    ctx_block_ret: dictionary<u64, u32> = dictionary<u64, u32>{},
    ctx_site_paths: dictionary<u64, u32> = dictionary<u64, u32>{},
    ctx_base_edge_set: dictionary<CtxEdgeKey, bool> = dictionary<CtxEdgeKey, bool>{},
    ctx_written_edge_set: dictionary<CtxEdgeKey, bool> = dictionary<CtxEdgeKey, bool>{},
    ctx_src_base_edges: dictionary<u64, u32> = dictionary<u64, u32>{},
    ctx_src_written_edges: dictionary<u64, u32> = dictionary<u64, u32>{},
    // Interned symbols.
    syms: SymKey[>..] = [],
    sym_map: dictionary<SymKey, u32> = dictionary<SymKey, u32>{},
    // Interned sites (alloc sites).
    sites: SiteKey[>..] = [],
    site_map: dictionary<SiteKey, u32> = dictionary<SiteKey, u32>{},
    // Interned call sites.
    call_sites: CallSiteInfo[>..] = [],
    call_site_map: dictionary<SiteKey, u32> = dictionary<SiteKey, u32>{},
    // Interned bounded paths.
    paths: PathKey[>..] = [],
    path_map: dictionary<PathKey, u32> = dictionary<PathKey, u32>{},
    // Interned field spellings (UTF-8).
    field_names: Chars[>..] = [],
    field_name_map: dictionary<const u8[:], u32> = dictionary<const u8[:], u32>{},
    // Memoized pure-scalar type predicate keyed by `(unit << 32) | tid`.
    pure_scalar_cache: dictionary<u64, bool> = dictionary<u64, bool>{},
    // Interned effect op keys.
    op_keys: OpKeyData[>..] = [],
    op_key_map: dictionary<OpKeyData, u32> = dictionary<OpKeyData, u32>{},
    // Callable definitions.
    fn_defs: FnDef[>..] = [],
    body_fn_map: dictionary<BindingRef, u32> = dictionary<BindingRef, u32>{},
    closure_fn_map: dictionary<u64, u32> = dictionary<u64, u32>{},
    spark_fn_map: dictionary<u64, u32> = dictionary<u64, u32>{},
    // Lazy whole-program index of associated methods & contract implementations.
    assoc_index_built: bool = false,
    assoc_entries: AssocEntry[>..] = [],
    assoc_by_name: dictionary<u32, u32> = dictionary<u32, u32>{},
    assoc_op_head: u32 = 0,
    impl_entries: ImplMemEntry[>..] = [],
    impl_by_name: dictionary<u32, u32> = dictionary<u32, u32>{},
    impl_by_contract: dictionary<u64, u32> = dictionary<u64, u32>{},
    // Contexts & worklist.
    ctxs: FnCtx[>..] = [],
    contexts_per_fn: u32[>..] = [],
    fn_ctx_head: u32[>..] = [],
    worklist: u32[>..] = [],
    // Tracked spark checks.
    spark_checks: SparkCheck[>..] = [],
    // Tracked globals & pool-initializer dependencies.
    pool_globals: BindingRef[>..] = [],
    pool_contains_globals: dictionary<u32, u32> = dictionary<u32, u32>{},
    // Hard failure latched during context creation / limits.
    fatal_issue: Issue = Issue {},
}

// ---- Basic Pool & Linked-Set Helpers ----

fn ctxKey(ctx_id: u32, item: u32) -> u64 {
    return ((ctx_id as u64) << 32) | (item as u64);
}

fn listHas(st: const Analyzer&, head: u32, val: u32) -> bool {
    var cur = head;
    while cur != 0 {
        let node = st.u32_nodes[cur];
        if node.val == val { return true; }
        cur = node.next;
    }
    return false;
}

fn listLen(st: const Analyzer&, head: u32) -> i64 {
    var count: i64 = 0;
    var cur = head;
    while cur != 0 {
        count += 1;
        cur = st.u32_nodes[cur].next;
    }
    return count;
}

fn listAdd(st: Analyzer&, head: u32&, val: u32) -> bool {
    if listHas(st, head, val) { return false; }
    let idx = st.u32_nodes.len as u32;
    st.u32_nodes.push(U32Node { val: val, next: head });
    head = idx;
    return true;
}

fn listSingle(st: Analyzer&, val: u32) -> u32 {
    let idx = st.u32_nodes.len as u32;
    st.u32_nodes.push(U32Node { val: val, next: 0 });
    return idx;
}

fn listUnionHead(st: Analyzer&, dst: u32&, src: u32) -> bool {
    var changed = false;
    var cur = src;
    while cur != 0 {
        let val = st.u32_nodes[cur].val;
        let nxt = st.u32_nodes[cur].next;
        if listAdd(st, dst, val) { changed = true; }
        cur = nxt;
    }
    return changed;
}

fn listEqual(st: const Analyzer&, a: u32, b: u32) -> bool {
    if listLen(st, a) != listLen(st, b) { return false; }
    var cur = a;
    while cur != 0 {
        if !listHas(st, b, st.u32_nodes[cur].val) { return false; }
        cur = st.u32_nodes[cur].next;
    }
    return true;
}

fn edgeListHas(st: const Analyzer&, head: u32, e: Edge) -> bool {
    var cur = head;
    while cur != 0 {
        let en = st.edge_nodes[cur];
        if en.edge.src == e.src && en.edge.lbl == e.lbl && en.edge.dst == e.dst { return true; }
        cur = en.next;
    }
    return false;
}

fn edgeListLen(st: const Analyzer&, head: u32) -> i64 {
    var count: i64 = 0;
    var cur = head;
    while cur != 0 {
        count += 1;
        cur = st.edge_nodes[cur].next;
    }
    return count;
}

fn edgeListEqual(st: const Analyzer&, a: u32, b: u32) -> bool {
    if edgeListLen(st, a) != edgeListLen(st, b) { return false; }
    var cur = a;
    while cur != 0 {
        if !edgeListHas(st, b, st.edge_nodes[cur].edge) { return false; }
        cur = st.edge_nodes[cur].next;
    }
    return true;
}

fn getBindingHead(st: const Analyzer&, ctx_id: u32, binding: u32) -> u32 {
    let found .= st.ctx_binding_pts.get(ctxKey(ctx_id, binding));
    if found { let h: u32 = found; return h; }
    return 0;
}

fn addBindingSym(st: Analyzer&, ctx_id: u32, binding: u32, val: u32) -> bool {
    if binding == 0 { return false; }
    let key = ctxKey(ctx_id, binding);
    var head: u32 = 0;
    let found .= st.ctx_binding_pts.get(key);
    if found { let h: u32 = found; head = h; }
    else { let _ = listAdd(st, st.ctxs[ctx_id].touched_bindings_head, binding); }
    if !listAdd(st, head, val) { return false; }
    st.ctx_binding_pts.insert(key, head);
    return true;
}

fn unionBindingHead(st: Analyzer&, ctx_id: u32, binding: u32, src_head: u32) -> bool {
    if binding == 0 || src_head == 0 { return false; }
    let key = ctxKey(ctx_id, binding);
    var head: u32 = 0;
    let found .= st.ctx_binding_pts.get(key);
    if found { let h: u32 = found; head = h; }
    else { let _ = listAdd(st, st.ctxs[ctx_id].touched_bindings_head, binding); }
    let changed = listUnionHead(st, head, src_head);
    if changed { st.ctx_binding_pts.insert(key, head); }
    return changed;
}

fn internSym(st: Analyzer&, key: SymKey) -> u32 {
    let found .= st.sym_map.get(key);
    if found { let id: u32 = found; return id; }
    let id = st.syms.len as u32;
    st.syms.push(key);
    st.sym_map.insert(key, id);
    return id;
}

fn symEmptyEnv(st: Analyzer&) -> u32 { return internSym(st, SymKey { kind: SYM_EMPTY_ENV }); }
fn symParam(st: Analyzer&, j: u32) -> u32 { return internSym(st, SymKey { kind: SYM_PARAM, a: j }); }
fn symCapture(st: Analyzer&, i: u32) -> u32 { return internSym(st, SymKey { kind: SYM_CAPTURE, a: i }); }
fn symGlobal(st: Analyzer&, unit: u32, binding: u32) -> u32 { return internSym(st, SymKey { kind: SYM_GLOBAL, a: unit, b: binding }); }
fn symChild(st: Analyzer&, root: u32) -> u32 { return internSym(st, SymKey { kind: SYM_CHILD, a: root }); }
fn symParamEnv(st: Analyzer&, j: u32, target_fn: u32) -> u32 { return internSym(st, SymKey { kind: SYM_PARAM_ENV, a: j, b: target_fn }); }
fn symCapNode(st: Analyzer&, j: u32, target_fn: u32, cap_i: u32) -> u32 { return internSym(st, SymKey { kind: SYM_CAP_NODE, a: j, b: target_fn, c: cap_i }); }
fn symHandlerCap(st: Analyzer&, frame: u32, cap_i: u32) -> u32 { return internSym(st, SymKey { kind: SYM_HANDLER_CAP, a: frame, b: cap_i }); }
fn symHandlerCell(st: Analyzer&, frame: u32) -> u32 { return internSym(st, SymKey { kind: SYM_HANDLER_CELL, a: frame }); }
fn symSumAlloc(st: Analyzer&, path_id: u32, orig_site: u32) -> u32 { return internSym(st, SymKey { kind: SYM_SUM_ALLOC, a: path_id, b: orig_site }); }
fn symCalleeFresh(st: Analyzer&, call_site: u32, path_id: u32, orig_site: u32) -> u32 { return internSym(st, SymKey { kind: SYM_CALLEE_FRESH, a: call_site, b: path_id, c: orig_site }); }
fn symFnVal(st: Analyzer&, fn_id: u32, env_sym: u32, applied: u8) -> u32 { return internSym(st, SymKey { kind: SYM_FN_VAL, sub: applied, a: fn_id, b: env_sym }); }
fn symSumFn(st: Analyzer&, fn_id: u32, env_sym: u32, applied: u8) -> u32 { return internSym(st, SymKey { kind: SYM_SUM_FN, sub: applied, a: fn_id, b: env_sym }); }
fn symOpVal(st: Analyzer&, op_key: u32) -> u32 { return internSym(st, SymKey { kind: SYM_OP_VAL, a: op_key }); }
fn symCtorFn(st: Analyzer&, unit: u32, ctor_idx: u32) -> u32 { return internSym(st, SymKey { kind: SYM_CTOR_FN, a: unit, b: ctor_idx }); }
fn symPrimFn(st: Analyzer&, unit: u32, prim_idx: u32) -> u32 { return internSym(st, SymKey { kind: SYM_PRIM_FN, a: unit, b: prim_idx }); }

fn internSite(st: Analyzer&, unit: u32, node: u32, sub: u32) -> u32 {
    let key = SiteKey { unit: unit, node: node, sub: sub };
    let found .= st.site_map.get(key);
    if found { let id: u32 = found; return id; }
    let id = st.sites.len as u32;
    st.sites.push(key);
    st.site_map.insert(key, id);
    return id;
}

fn symFresh(st: Analyzer&, unit: u32, node: u32, sub: u32) -> u32 {
    let site_id = internSite(st, unit, node, sub);
    return internSym(st, SymKey { kind: SYM_FRESH, a: site_id });
}

fn internCallSite(st: Analyzer&, enclosing_fn: u32, unit: u32, node: u32, sub: u32) -> u32 {
    let key = SiteKey { unit: unit, node: node, sub: sub };
    let found .= st.call_site_map.get(key);
    if found { let id: u32 = found; return id; }
    let id = st.call_sites.len as u32;
    st.call_sites.push(CallSiteInfo { enclosing_fn: enclosing_fn, unit: unit, node: node });
    st.call_site_map.insert(key, id);
    return id;
}

fn internPath(st: Analyzer&, pk: PathKey) -> u32 {
    let found .= st.path_map.get(pk);
    if found { let id: u32 = found; return id; }
    let id = st.paths.len as u32;
    st.paths.push(pk);
    st.path_map.insert(pk, id);
    return id;
}

// Constant cycle-free k-CFA prepend `extend_path(c, path)` (§2.5).
fn extendPath(st: Analyzer&, call_site: u32, path_id: u32) -> u32 {
    if path_id == PATH_WILDCARD { return PATH_WILDCARD; }
    let enc = st.call_sites[call_site].enclosing_fn;
    let prev = st.paths[path_id];
    var out: u32[3] = [call_site, 0, 0];
    var len: i64 = 1;
    var prev_arr: u32[3] = [prev.c0, prev.c1, prev.c2];
    for i in 0..(prev.len as i64) {
        if len >= K_CALL_DEPTH { break; }
        let ck = prev_arr[i];
        if st.call_sites[ck].enclosing_fn == enc { break; }
        out[len] = ck;
        len += 1;
    }
    return internPath(st, PathKey { len: len as u8, c0: out[0], c1: out[1], c2: out[2] });
}

fn internFieldLabel(st: Analyzer&, name: Chars) -> u32 {
    let found .= st.field_name_map.get(name);
    if found { let lbl: u32 = found; return lbl; }
    let idx = st.field_names.len as u32;
    let lbl = LBL_FIELD_BASE + idx;
    st.field_names.push(name);
    st.field_name_map.insert(name, lbl);
    return lbl;
}

fn internOpKey(st: Analyzer&, op_val: blot_check_core::OperationValue) -> u32 {
    let key = OpKeyData { identity: op_val.identity, instance: op_val.instance };
    let found .= st.op_key_map.get(key);
    if found { let id: u32 = found; return id; }
    let id = st.op_keys.len as u32;
    st.op_keys.push(key);
    st.op_key_map.insert(key, id);
    return id;
}

fn hasUnit(units: const Module[:], unit: u32) -> bool {
    return unit != 0 && (unit as i64) <= units.len;
}

fn isPoolType(m: const Module&, tid: TId) -> bool {
    if (tid as i64) >= m.types.nodes.len { return false; }
    var cur = tid;
    for _ in 0..16 {
        let n = m.types.node(cur);
        if n.tag == blot_check_types::Tag.usage || n.tag == blot_check_types::Tag.forall { cur = n.a; continue; }
        break;
    }
    return blot_check_storage_types::isArray(m.types, cur);
}

// Sound closed-world check: returns true ONLY when `tid` is provably a concrete
// pure-data value type that cannot hold any heap storage, mutable array, view,
// closure, effect operation, or uninstantiated type parameter.
recursive fn isPureScalarValueType(units: const Module[:], unit: u32, tid: TId, depth: i64) -> bool {
    if depth > 16 || !hasUnit(units, unit) { return false; }
    let m .= units[unit - 1];
    if (tid as i64) >= m.types.nodes.len { return false; }
    let n = m.types.node(tid);
    match n.tag {
        unit, boolean, unsigned32, floating32, never => { return true; },
        usage => { return isPureScalarValueType(units, unit, n.a, depth + 1); },
        product => {
            for c in m.types.list(blot_check_types::List { start: n.a, len: n.b }) {
                if !isPureScalarValueType(units, unit, c, depth + 1) { return false; }
            }
            return true;
        },
        record => {
            for i in 0..(n.b as i64) {
                if !isPureScalarValueType(units, unit, m.types.recordField(n, i).ty, depth + 1) { return false; }
            }
            return true;
        },
        nominal => {
            if blot_check_storage_types::info(m.types, tid).present { return false; }
            if n.a == 0xffffffff || !hasUnit(units, n.a) { return false; }
            let args = m.types.nominalArguments(n);
            if args.len != 0 { return false; }
            let dm .= units[n.a - 1];
            let want = Identity { unit: n.a, decl: n.b };
            for i in 1..dm.nominals.len {
                if dm.nominals[i].identity == want {
                    if dm.nominals[i].is_opaque || dm.nominals[i].parameters.len != 0 { return false; }
                    for cid in dm.nominalConstructors(i as u32) {
                        let c = dm.constructor(cid);
                        if c.payload != 0 && !isPureScalarValueType(units, n.a, c.payload, depth + 1) { return false; }
                    }
                    return true;
                }
            }
            return false;
        },
        _ => { return false; },
    }
}

fn isPureScalarCached(st: Analyzer&, units: const Module[:], unit: u32, tid: TId) -> bool {
    let key = ((unit as u64) << 32) | (tid as u64);
    let found .= st.pure_scalar_cache.get(key);
    if found { let v: bool = found; return v; }
    let v = isPureScalarValueType(units, unit, tid, 0);
    st.pure_scalar_cache.insert(key, v);
    return v;
}

recursive fn typeHasMutableArray(units: const Module[:], unit: u32, tid: TId, depth: i64) -> bool {
    if depth > 64 || !hasUnit(units, unit) { return false; }
    let m .= units[unit - 1];
    if (tid as i64) >= m.types.nodes.len { return false; }
    let n = m.types.node(tid);
    match n.tag {
        usage, forall => { return typeHasMutableArray(units, unit, n.a, depth + 1); },
        array => { return typeHasMutableArray(units, unit, n.a, depth + 1); },
        product => {
            for c in m.types.list(blot_check_types::List { start: n.a, len: n.b }) {
                if typeHasMutableArray(units, unit, c, depth + 1) { return true; }
            }
            return false;
        },
        record => {
            for i in 0..(n.b as i64) {
                if typeHasMutableArray(units, unit, m.types.recordField(n, i).ty, depth + 1) { return true; }
            }
            return false;
        },
        nominal => {
            let si = blot_check_storage_types::info(m.types, tid);
            if si.present {
                return typeHasMutableArray(units, unit, si.value.element, depth + 1);
            }
            if !hasUnit(units, n.a) || n.a == 0xffffffff { return false; }
            for arg in m.types.nominalArguments(n) {
                if typeHasMutableArray(units, unit, arg, depth + 1) { return true; }
            }
            let dm .= units[n.a - 1];
            for i in 1..dm.nominals.len {
                if dm.nominals[i].identity == (Identity { unit: n.a, decl: n.b }) {
                    for cid in dm.nominalConstructors(i as u32) {
                        let c = dm.constructor(cid);
                        if c.payload != 0 && typeHasMutableArray(units, n.a, c.payload, depth + 1) { return true; }
                    }
                    break;
                }
            }
            return false;
        },
        _ => { return false; },
    }
}

fn isPreExisting(st: const Analyzer&, ctx_id: u32, sym: u32) -> bool {
    return st.ctx_pre_existing.contains(ctxKey(ctx_id, sym));
}

fn addBaseEdge(st: Analyzer&, ctx_id: u32, src: u32, lbl: u32, dst: u32) {
    let key = CtxEdgeKey { ctx_id: ctx_id, src: src, lbl: lbl, dst: dst };
    if st.ctx_base_edge_set.contains(key) { return; }
    st.ctx_base_edge_set.insert(key, true);
    let skey = ctxKey(ctx_id, src);
    var prev_src: u32 = 0;
    let sopt .= st.ctx_src_base_edges.get(skey);
    if sopt { let h: u32 = sopt; prev_src = h; }
    let idx = st.edge_nodes.len as u32;
    st.edge_nodes.push(EdgeNode { edge: Edge { src: src, lbl: lbl, dst: dst }, next: st.ctxs[ctx_id].base_edges_head, next_src: prev_src });
    st.ctxs[ctx_id].base_edges_head = idx;
    st.ctx_src_base_edges.insert(skey, idx);
}

fn addWrittenEdge(st: Analyzer&, ctx_id: u32, src: u32, lbl: u32, dst: u32) -> bool {
    let key = CtxEdgeKey { ctx_id: ctx_id, src: src, lbl: lbl, dst: dst };
    if st.ctx_written_edge_set.contains(key) { return false; }
    st.ctx_written_edge_set.insert(key, true);
    let skey = ctxKey(ctx_id, src);
    var prev_src: u32 = 0;
    let sopt .= st.ctx_src_written_edges.get(skey);
    if sopt { let h: u32 = sopt; prev_src = h; }
    let idx = st.edge_nodes.len as u32;
    st.edge_nodes.push(EdgeNode { edge: Edge { src: src, lbl: lbl, dst: dst }, next: st.ctxs[ctx_id].written_edges_head, next_src: prev_src });
    st.ctxs[ctx_id].written_edges_head = idx;
    st.ctx_src_written_edges.insert(skey, idx);
    return true;
}

fn addWrittenEdgesHeads(st: Analyzer&, ctx_id: u32, src_head: u32, lbl: u32, dst_head: u32) -> bool {
    var changed = false;
    var sc = src_head;
    while sc != 0 {
        let s = st.u32_nodes[sc].val;
        let sn = st.u32_nodes[sc].next;
        var dc = dst_head;
        while dc != 0 {
            let d = st.u32_nodes[dc].val;
            let dn = st.u32_nodes[dc].next;
            if addWrittenEdge(st, ctx_id, s, lbl, d) { changed = true; }
            dc = dn;
        }
        sc = sn;
    }
    return changed;
}

fn addWrittenEdgesSingleSrc(st: Analyzer&, ctx_id: u32, src: u32, lbl: u32, dst_head: u32) -> bool {
    var changed = false;
    var dc = dst_head;
    while dc != 0 {
        let d = st.u32_nodes[dc].val;
        let dn = st.u32_nodes[dc].next;
        if addWrittenEdge(st, ctx_id, src, lbl, d) { changed = true; }
        dc = dn;
    }
    return changed;
}

fn addWrittenEdgesSingleDst(st: Analyzer&, ctx_id: u32, src_head: u32, lbl: u32, dst: u32) -> bool {
    var changed = false;
    var sc = src_head;
    while sc != 0 {
        let s = st.u32_nodes[sc].val;
        let sn = st.u32_nodes[sc].next;
        if addWrittenEdge(st, ctx_id, s, lbl, dst) { changed = true; }
        sc = sn;
    }
    return changed;
}

fn registerPreExistingRoot(st: Analyzer&, ctx_id: u32, root: u32, add_child: bool) {
    st.ctx_pre_existing.insert(ctxKey(ctx_id, root), true);
    if add_child {
        let ch = symChild(st, root);
        st.ctx_pre_existing.insert(ctxKey(ctx_id, ch), true);
        addBaseEdge(st, ctx_id, root, LBL_ANY, ch);
        addBaseEdge(st, ctx_id, ch, LBL_ANY, ch);
    }
}

// ---- Single-Step & Transitive Graph Queries (§2.5) — all return `u32` list heads ----

fn stepLabelHead(st: Analyzer&, ctx_id: u32, seeds_head: u32, want_lbl: u32) -> u32 {
    if seeds_head == 0 { return 0; }
    var out: u32 = 0;
    var sc = seeds_head;
    while sc != 0 {
        let src = st.u32_nodes[sc].val;
        let sn = st.u32_nodes[sc].next;
        let skey = ctxKey(ctx_id, src);
        let bopt .= st.ctx_src_base_edges.get(skey);
        if bopt {
            var ec: u32 = bopt;
            while ec != 0 {
                let en = st.edge_nodes[ec];
                if en.edge.lbl == want_lbl || en.edge.lbl == LBL_ANY {
                    let _ = listAdd(st, out, en.edge.dst);
                }
                ec = en.next_src;
            }
        }
        let wopt .= st.ctx_src_written_edges.get(skey);
        if wopt {
            var ec: u32 = wopt;
            while ec != 0 {
                let en = st.edge_nodes[ec];
                if en.edge.lbl == want_lbl || en.edge.lbl == LBL_ANY {
                    let _ = listAdd(st, out, en.edge.dst);
                }
                ec = en.next_src;
            }
        }
        sc = sn;
    }
    return out;
}

fn stepAnyHead(st: Analyzer&, ctx_id: u32, seeds_head: u32) -> u32 {
    return stepLabelHead(st, ctx_id, seeds_head, LBL_ANY);
}

fn stepElemHead(st: Analyzer&, ctx_id: u32, seeds_head: u32) -> u32 {
    return stepLabelHead(st, ctx_id, seeds_head, LBL_ELEM);
}

fn stepCtorHead(st: Analyzer&, ctx_id: u32, seeds_head: u32) -> u32 {
    return stepLabelHead(st, ctx_id, seeds_head, LBL_CTOR_PAYLOAD);
}

fn stepCaptureHead(st: Analyzer&, ctx_id: u32, seeds_head: u32, cap_i: u32) -> u32 {
    return stepLabelHead(st, ctx_id, seeds_head, LBL_CAPTURE_BASE + cap_i);
}

fn stepFieldHead(st: Analyzer&, ctx_id: u32, seeds_head: u32, field_lbl: u32) -> u32 {
    if seeds_head == 0 { return 0; }
    var expanded: u32 = 0;
    let _ = listUnionHead(st, expanded, seeds_head);
    let unwrapped = stepCtorHead(st, ctx_id, seeds_head);
    let _ = listUnionHead(st, expanded, unwrapped);
    return stepLabelHead(st, ctx_id, expanded, field_lbl);
}

fn stepTupleHead(st: Analyzer&, ctx_id: u32, seeds_head: u32, slot: u32) -> u32 {
    if seeds_head == 0 { return 0; }
    var expanded: u32 = 0;
    let _ = listUnionHead(st, expanded, seeds_head);
    let unwrapped = stepCtorHead(st, ctx_id, seeds_head);
    let _ = listUnionHead(st, expanded, unwrapped);
    return stepLabelHead(st, ctx_id, expanded, LBL_TUPLE_BASE + slot);
}

// Reflexive-transitive closure over BOTH `contains` (all labels) AND `FnVal(_, env_node) -> env_node` (§2.5).
fn reachIntoSet(st: const Analyzer&, ctx_id: u32, seeds_head: u32, seen: dictionary<u32, bool>&, visited: u32[>..]& ) {
    if seeds_head == 0 { return; }
    var sc = seeds_head;
    while sc != 0 {
        let s = st.u32_nodes[sc].val;
        if !seen.contains(s) { seen.insert(s, true); visited.push(s); }
        sc = st.u32_nodes[sc].next;
    }
    var cursor: i64 = 0;
    while cursor < visited.len {
        let cur = visited[cursor];
        cursor += 1;
        let sk = st.syms[cur];
        if sk.kind == SYM_FN_VAL {
            let env = sk.b;
            if !seen.contains(env) { seen.insert(env, true); visited.push(env); }
        }
        let skey = ctxKey(ctx_id, cur);
        let bopt .= st.ctx_src_base_edges.get(skey);
        if bopt {
            var ec: u32 = bopt;
            while ec != 0 {
                let en = st.edge_nodes[ec];
                if !seen.contains(en.edge.dst) { seen.insert(en.edge.dst, true); visited.push(en.edge.dst); }
                ec = en.next_src;
            }
        }
        let wopt .= st.ctx_src_written_edges.get(skey);
        if wopt {
            var ec: u32 = wopt;
            while ec != 0 {
                let en = st.edge_nodes[ec];
                if !seen.contains(en.edge.dst) { seen.insert(en.edge.dst, true); visited.push(en.edge.dst); }
                ec = en.next_src;
            }
        }
    }
}

fn reachHead(st: Analyzer&, ctx_id: u32, seeds_head: u32) -> u32 {
    if seeds_head == 0 { return 0; }
    var visited: u32[>..] = [];
    var seen: dictionary<u32, bool> = dictionary<u32, bool>{};
    reachIntoSet(st, ctx_id, seeds_head, seen, visited);
    var out: u32 = 0;
    for v in visited {
        let idx = st.u32_nodes.len as u32;
        st.u32_nodes.push(U32Node { val: v, next: out });
        out = idx;
    }
    return out;
}

// Strict transitive closure (>= 1 step over `contains` OR `FnVal(_, env_node) -> env_node`).
fn reachStrictHead(st: Analyzer&, ctx_id: u32, seeds_head: u32) -> u32 {
    if seeds_head == 0 { return 0; }
    var direct: u32 = 0;
    var sc = seeds_head;
    while sc != 0 {
        let cur = st.u32_nodes[sc].val;
        let sn = st.u32_nodes[sc].next;
        let sk = st.syms[cur];
        if sk.kind == SYM_FN_VAL { let _ = listAdd(st, direct, sk.b); }
        let skey = ctxKey(ctx_id, cur);
        let bopt .= st.ctx_src_base_edges.get(skey);
        if bopt {
            var ec: u32 = bopt;
            while ec != 0 {
                let en = st.edge_nodes[ec];
                let _ = listAdd(st, direct, en.edge.dst);
                ec = en.next_src;
            }
        }
        let wopt .= st.ctx_src_written_edges.get(skey);
        if wopt {
            var ec: u32 = wopt;
            while ec != 0 {
                let en = st.edge_nodes[ec];
                let _ = listAdd(st, direct, en.edge.dst);
                ec = en.next_src;
            }
        }
        sc = sn;
    }
    return reachHead(st, ctx_id, direct);
}

// ---- Lazy Per-Unit Registration of Callables (Bodies, Closures, Sparks) ----

fn initAnalyzerSentinels(st: Analyzer&) {
    st.u32_nodes.push(U32Node {});
    st.edge_nodes.push(EdgeNode {});
    st.caller_nodes.push(CallerNode {});
    st.assoc_entries.push(AssocEntry {});
    st.impl_entries.push(ImplMemEntry {});
    let _ = symEmptyEnv(st);
    let _ = internPath(st, PathKey { len: 0 });
    let _ = internPath(st, PathKey { len: 0xff });
}

fn ensureUnitRegistered(st: Analyzer&, units: const Module[:], unit: u32) {
    if !hasUnit(units, unit) { return; }
    let sentinel = BindingRef { unit: unit, binding: 0 };
    if st.body_fn_map.contains(sentinel) { return; }
    st.body_fn_map.insert(sentinel, 0);
    let m .= units[unit - 1];
    for bi in 1..m.bodies.len {
        let body = m.bodies[bi];
        let fn_id = st.fn_defs.len as u32;
        let pstart = st.fn_bindings.len as u32;
        for p in m.bodyParameters(body) { st.fn_bindings.push(p.binding); }
        let plen = (st.fn_bindings.len as u32) - pstart;
        st.fn_defs.push(FnDef {
            kind: FN_BODY,
            unit: unit,
            binding: body.binding,
            node_id: bi as u32,
            root: body.root,
            is_function: body.is_function,
            param_start: pstart,
            param_len: plen,
            span: body.span,
        });
        st.contexts_per_fn.push(0);
        st.fn_ctx_head.push(0);
        st.body_fn_map.insert(BindingRef { unit: unit, binding: body.binding }, fn_id);
    }
    for nid in 1..m.nodes.len {
        let n = m.nodes[nid];
        if n.tag == blot_check_core::Tag.closure {
            let cl = m.closure(nid as u32);
            let fn_id = st.fn_defs.len as u32;
            let pstart = st.fn_bindings.len as u32;
            st.fn_bindings.push(cl.parameter.binding);
            let cstart = st.fn_bindings.len as u32;
            for cb in m.closureCaptures(nid as u32) { st.fn_bindings.push(cb); }
            let clen = (st.fn_bindings.len as u32) - cstart;
            st.fn_defs.push(FnDef {
                kind: FN_CLOSURE,
                unit: unit,
                node_id: nid as u32,
                root: cl.body,
                is_function: true,
                param_start: pstart,
                param_len: 1,
                capture_start: cstart,
                capture_len: clen,
                span: m.span(nid as u32),
            });
            st.contexts_per_fn.push(0);
            st.fn_ctx_head.push(0);
            let key = ((unit as u64) << 32) | (nid as u64);
            st.closure_fn_map.insert(key, fn_id);
        } else if n.tag == blot_check_core::Tag.spark {
            let si = m.sparkInfo(nid as u32);
            let fn_id = st.fn_defs.len as u32;
            let cstart = st.fn_bindings.len as u32;
            for cb in m.sparkCaptures(nid as u32) { st.fn_bindings.push(cb); }
            let clen = (st.fn_bindings.len as u32) - cstart;
            st.fn_defs.push(FnDef {
                kind: FN_SPARK,
                unit: unit,
                node_id: nid as u32,
                root: si.body,
                is_function: false,
                capture_start: cstart,
                capture_len: clen,
                span: m.span(nid as u32),
            });
            st.contexts_per_fn.push(0);
            st.fn_ctx_head.push(0);
            let key = ((unit as u64) << 32) | (nid as u64);
            st.spark_fn_map.insert(key, fn_id);
        }
    }
}

fn lookupBodyFn(st: Analyzer&, units: const Module[:], target: BindingRef) -> u32, bool {
    if target.binding == 0 { return 0, false; }
    ensureUnitRegistered(st, units, target.unit);
    let opt .= st.body_fn_map.get(target);
    if !opt { return 0, false; }
    let fid: u32 = opt;
    return fid, true;
}

fn specsEqual(a: const CallableSpec[:], b: const CallableSpec[:]) -> bool {
    if a.len != b.len { return false; }
    for i in 0..a.len {
        if a[i].slot != b[i].slot || a[i].tag_kind != b[i].tag_kind || a[i].applied != b[i].applied || a[i].target_a != b[i].target_a || a[i].target_b != b[i].target_b { return false; }
    }
    return true;
}

fn handlersEqual(a: const HandlerSpec[:], b: const HandlerSpec[:]) -> bool {
    if a.len != b.len { return false; }
    for i in 0..a.len {
        if a[i].op_key != b[i].op_key || a[i].kind != b[i].kind || a[i].fn_id != b[i].fn_id || a[i].applied != b[i].applied || a[i].cap_count != b[i].cap_count { return false; }
    }
    return true;
}

fn bindNestedCallableEnv(st: Analyzer&, ctx_id: u32, base_slot: u32, pe: u32, target_fn: u32, applied: u8, cspecs: const CallableSpec[:]) {
    var own_caps: i64 = 0;
    if st.fn_defs[target_fn].kind == FN_CLOSURE { own_caps = st.fn_defs[target_fn].capture_len as i64; }
    let k_caps = own_caps + (applied as i64);
    for ci in 0..k_caps {
        var nslot: u32 = 0xffffffff;
        if ci < 64 {
            if base_slot >= 1000 && base_slot < 2000 {
                nslot = 100000 + (base_slot - 1000) * 64 + (ci as u32);
            } else if base_slot < 1000 {
                nslot = 2000 + base_slot * 64 + (ci as u32);
            }
        }
        var nested_spec = false;
        if nslot != 0xffffffff {
            for ncs in cspecs {
                if ncs.slot != nslot { continue; }
                nested_spec = true;
                if ncs.tag_kind == 0 {
                    let npe = symParamEnv(st, nslot, ncs.target_a);
                    registerPreExistingRoot(st, ctx_id, npe, false);
                    let nfv = symFnVal(st, ncs.target_a, npe, ncs.applied);
                    addBaseEdge(st, ctx_id, pe, LBL_CAPTURE_BASE + (ci as u32), nfv);
                    var n_own: i64 = 0;
                    if st.fn_defs[ncs.target_a].kind == FN_CLOSURE { n_own = st.fn_defs[ncs.target_a].capture_len as i64; }
                    let n_caps = n_own + (ncs.applied as i64);
                    for ki in 0..n_caps {
                        let ncn = symCapNode(st, nslot, ncs.target_a, ki as u32);
                        registerPreExistingRoot(st, ctx_id, ncn, true);
                        addBaseEdge(st, ctx_id, npe, LBL_CAPTURE_BASE + (ki as u32), ncn);
                    }
                } else if ncs.tag_kind == 1 {
                    addBaseEdge(st, ctx_id, pe, LBL_CAPTURE_BASE + (ci as u32), symOpVal(st, ncs.target_a));
                } else if ncs.tag_kind == 2 {
                    addBaseEdge(st, ctx_id, pe, LBL_CAPTURE_BASE + (ci as u32), symCtorFn(st, ncs.target_a, ncs.target_b));
                } else if ncs.tag_kind == 3 {
                    addBaseEdge(st, ctx_id, pe, LBL_CAPTURE_BASE + (ci as u32), symPrimFn(st, ncs.target_a, ncs.target_b));
                }
            }
        }
        if !nested_spec {
            let cn = symCapNode(st, base_slot, target_fn, ci as u32);
            registerPreExistingRoot(st, ctx_id, cn, true);
            addBaseEdge(st, ctx_id, pe, LBL_CAPTURE_BASE + (ci as u32), cn);
        }
    }
}

fn getOrCreateCtx(
    st: Analyzer&,
    fn_id: u32,
    cspecs: const CallableSpec[:],
    hspecs: const HandlerSpec[:],
    err_unit: u32,
    err_span: blot_check_core::Span
) -> u32, bool {
    if hspecs.len > MAX_HANDLER_DEPTH {
        if !st.fatal_issue.failed {
            st.fatal_issue = Issue { failed: true, unit: err_unit, span: err_span, code: blot_check_diagnostic_code::Code.purity_limit, message: "effect handler depth exceeds purity analyzer limit" };
        }
        return 0, false;
    }
    var cur_ci = st.fn_ctx_head[fn_id];
    while cur_ci != 0 {
        let ci = cur_ci - 1;
        let c = st.ctxs[ci];
        if specsEqual(st.ctx_cspecs[c.cspec_start..c.cspec_start + c.cspec_len], cspecs) &&
           handlersEqual(st.ctx_hspecs[c.hspec_start..c.hspec_start + c.hspec_len], hspecs) {
            return ci, true;
        }
        cur_ci = c.next_same_fn;
    }
    if (st.contexts_per_fn[fn_id] as i64) >= MAX_CONTEXTS_PER_FN {
        if !st.fatal_issue.failed {
            st.fatal_issue = Issue { failed: true, unit: err_unit, span: err_span, code: blot_check_diagnostic_code::Code.purity_limit, message: "higher-order context specialization exceeds purity analyzer limit" };
        }
        return 0, false;
    }
    st.contexts_per_fn[fn_id] += 1;
    let ctx_id = st.ctxs.len as u32;
    let cstart = st.ctx_cspecs.len as u32;
    for cs in cspecs { st.ctx_cspecs.push(cs); }
    let hstart = st.ctx_hspecs.len as u32;
    for hs in hspecs { st.ctx_hspecs.push(hs); }
    let prev_fn_ctx = st.fn_ctx_head[fn_id];
    st.ctxs.push(FnCtx {
        fn_id: fn_id,
        cspec_start: cstart,
        cspec_len: cspecs.len as u32,
        hspec_start: hstart,
        hspec_len: hspecs.len as u32,
        dirty: true,
        next_same_fn: prev_fn_ctx,
    });
    st.fn_ctx_head[fn_id] = ctx_id + 1;
    let def = st.fn_defs[fn_id];
    for pi in 0..(def.param_len as i64) {
        let pb = st.fn_bindings[(def.param_start as i64) + pi];
        var specialized = false;
        for cs in cspecs {
            if cs.slot == (pi as u32) {
                specialized = true;
                if cs.tag_kind == 0 {
                    let pe = symParamEnv(st, pi as u32, cs.target_a);
                    registerPreExistingRoot(st, ctx_id, pe, false);
                    let fv = symFnVal(st, cs.target_a, pe, cs.applied);
                    let _ = addBindingSym(st, ctx_id, pb, fv);
                    bindNestedCallableEnv(st, ctx_id, pi as u32, pe, cs.target_a, cs.applied, cspecs);
                } else if cs.tag_kind == 1 {
                    let _ = addBindingSym(st, ctx_id, pb, symOpVal(st, cs.target_a));
                } else if cs.tag_kind == 2 {
                    let _ = addBindingSym(st, ctx_id, pb, symCtorFn(st, cs.target_a, cs.target_b));
                } else if cs.tag_kind == 3 {
                    let _ = addBindingSym(st, ctx_id, pb, symPrimFn(st, cs.target_a, cs.target_b));
                }
            }
        }
        if !specialized {
            let p = symParam(st, pi as u32);
            registerPreExistingRoot(st, ctx_id, p, true);
            let _ = addBindingSym(st, ctx_id, pb, p);
        }
    }
    for ci in 0..(def.capture_len as i64) {
        let cb = st.fn_bindings[(def.capture_start as i64) + ci];
        let cap_slot = 1000 + (ci as u32);
        var specialized = false;
        for cs in cspecs {
            if cs.slot == cap_slot {
                specialized = true;
                if cs.tag_kind == 0 {
                    let pe = symParamEnv(st, cap_slot, cs.target_a);
                    registerPreExistingRoot(st, ctx_id, pe, false);
                    let fv = symFnVal(st, cs.target_a, pe, cs.applied);
                    let _ = addBindingSym(st, ctx_id, cb, fv);
                    bindNestedCallableEnv(st, ctx_id, cap_slot, pe, cs.target_a, cs.applied, cspecs);
                } else if cs.tag_kind == 1 {
                    let _ = addBindingSym(st, ctx_id, cb, symOpVal(st, cs.target_a));
                }
            }
        }
        if !specialized {
            let cap = symCapture(st, ci as u32);
            registerPreExistingRoot(st, ctx_id, cap, true);
            let _ = addBindingSym(st, ctx_id, cb, cap);
        }
    }
    for hi in 0..hspecs.len {
        let hs = hspecs[hi];
        if hs.kind == HANDLER_CLOSURE {
            for ci in 0..(hs.cap_count as i64) {
                let hc = symHandlerCap(st, hi as u32, ci as u32);
                registerPreExistingRoot(st, ctx_id, hc, true);
            }
        } else {
            let cell = symHandlerCell(st, hi as u32);
            registerPreExistingRoot(st, ctx_id, cell, true);
        }
    }
    st.worklist.push(ctx_id);
    return ctx_id, true;
}

fn markCtxDirty(st: Analyzer&, ctx_id: u32) {
    if !st.ctxs[ctx_id].dirty {
        st.ctxs[ctx_id].dirty = true;
        st.worklist.push(ctx_id);
    }
}

fn registerCaller(st: Analyzer&, callee_ctx: u32, caller_ctx: u32, call_site: u32) {
    var cur = st.ctxs[callee_ctx].callers_head;
    while cur != 0 {
        let rec = st.caller_nodes[cur];
        if rec.caller_ctx == caller_ctx && rec.call_site == call_site { return; }
        cur = rec.next;
    }
    let idx = st.caller_nodes.len as u32;
    st.caller_nodes.push(CallerNode { caller_ctx: caller_ctx, call_site: call_site, next: st.ctxs[callee_ctx].callers_head });
    st.ctxs[callee_ctx].callers_head = idx;
}

// ---- Monotone Widening Quotient & Caller Remapping (§2.5) ----

recursive fn remapSymWildcard(st: Analyzer&, sym: u32, call_site: u32, orig_site: u32) -> u32 {
    let sk = st.syms[sym];
    if sk.kind == SYM_CALLEE_FRESH && sk.a == call_site && sk.c == orig_site && sk.b != PATH_WILDCARD {
        return symCalleeFresh(st, call_site, PATH_WILDCARD, orig_site);
    }
    if sk.kind == SYM_FN_VAL {
        let new_env = remapSymWildcard(st, sk.b, call_site, orig_site);
        if new_env != sk.b { return symFnVal(st, sk.a, new_env, sk.sub); }
    }
    return sym;
}

fn remapListWildcard(st: Analyzer&, head: u32&, call_site: u32, orig_site: u32) -> bool {
    var changed = false;
    var new_head: u32 = 0;
    var cur = head;
    while cur != 0 {
        let x = st.u32_nodes[cur].val;
        let nxt = st.u32_nodes[cur].next;
        let nx = remapSymWildcard(st, x, call_site, orig_site);
        if nx != x { changed = true; }
        let _ = listAdd(st, new_head, nx);
        cur = nxt;
    }
    if changed { head = new_head; }
    return changed;
}

fn remapCallerForWidenedSite(st: Analyzer&, caller_ctx: u32, call_site: u32, orig_site: u32) {
    var changed = false;
    var bc = st.ctxs[caller_ctx].touched_bindings_head;
    while bc != 0 {
        let b = st.u32_nodes[bc].val;
        let bn = st.u32_nodes[bc].next;
        var bhead = getBindingHead(st, caller_ctx, b);
        if remapListWildcard(st, bhead, call_site, orig_site) {
            st.ctx_binding_pts.insert(ctxKey(caller_ctx, b), bhead);
            changed = true;
        }
        bc = bn;
    }
    var rhead = st.ctxs[caller_ctx].ret_pts_head;
    if remapListWildcard(st, rhead, call_site, orig_site) {
        st.ctxs[caller_ctx].ret_pts_head = rhead;
        changed = true;
    }
    var mhead = st.ctxs[caller_ctx].mutated_head;
    if remapListWildcard(st, mhead, call_site, orig_site) {
        st.ctxs[caller_ctx].mutated_head = mhead;
        changed = true;
    }
    let emark = st.edge_stack.len;
    var ec = st.ctxs[caller_ctx].written_edges_head;
    var edge_changed = false;
    while ec != 0 {
        let e = st.edge_nodes[ec].edge;
        st.edge_stack.push(e);
        let ns = remapSymWildcard(st, e.src, call_site, orig_site);
        let nd = remapSymWildcard(st, e.dst, call_site, orig_site);
        if ns != e.src || nd != e.dst { edge_changed = true; }
        ec = st.edge_nodes[ec].next;
    }
    if edge_changed {
        for ei in emark..st.edge_stack.len {
            let e = st.edge_stack[ei];
            st.ctx_written_edge_set.remove(CtxEdgeKey { ctx_id: caller_ctx, src: e.src, lbl: e.lbl, dst: e.dst });
            st.ctx_src_written_edges.remove(ctxKey(caller_ctx, e.src));
        }
        st.ctxs[caller_ctx].written_edges_head = 0;
        for ei in emark..st.edge_stack.len {
            let e = st.edge_stack[ei];
            let ns = remapSymWildcard(st, e.src, call_site, orig_site);
            let nd = remapSymWildcard(st, e.dst, call_site, orig_site);
            let _ = addWrittenEdge(st, caller_ctx, ns, e.lbl, nd);
        }
        changed = true;
    }
    st.edge_stack.resize(emark);
    if changed { markCtxDirty(st, caller_ctx); }
}

// Total boundary projection `π_static : Nodes(fn) -> B_static(fn)` (§2.5).
recursive fn piStatic(st: Analyzer&, ctx_id: u32, sym: u32) -> u32 {
    let sk = st.syms[sym];
    if sk.kind == SYM_EMPTY_ENV || sk.kind == SYM_OP_VAL || sk.kind == SYM_CTOR_FN || sk.kind == SYM_PRIM_FN || sk.kind == SYM_GLOBAL {
        return sym;
    }
    if isPreExisting(st, ctx_id, sym) { return sym; }
    if sk.kind == SYM_FRESH {
        let orig_site = sk.a;
        if st.ctx_widened_sites.contains(ctxKey(ctx_id, orig_site)) {
            return symSumAlloc(st, PATH_WILDCARD, orig_site);
        }
        return symSumAlloc(st, PATH_EMPTY, orig_site);
    }
    if sk.kind == SYM_CALLEE_FRESH {
        let call_site = sk.a;
        let path_id = sk.b;
        let orig_site = sk.c;
        if st.ctx_widened_sites.contains(ctxKey(ctx_id, orig_site)) {
            return symSumAlloc(st, PATH_WILDCARD, orig_site);
        }
        let ext = extendPath(st, call_site, path_id);
        return symSumAlloc(st, ext, orig_site);
    }
    if sk.kind == SYM_FN_VAL {
        let env_b = piStatic(st, ctx_id, sk.b);
        return symSumFn(st, sk.a, env_b, sk.sub);
    }
    return sym;
}

recursive fn checkWideningLatch(st: Analyzer&, ctx_id: u32, sum_sym: u32) -> bool {
    let sk = st.syms[sum_sym];
    if sk.kind == SYM_SUM_FN { return checkWideningLatch(st, ctx_id, sk.b); }
    if sk.kind != SYM_SUM_ALLOC { return false; }
    let path_id = sk.a;
    let orig_site = sk.b;
    let wkey = ctxKey(ctx_id, orig_site);
    if st.ctx_widened_sites.contains(wkey) { return false; }
    if path_id == PATH_WILDCARD {
        st.ctx_widened_sites.insert(wkey, true);
        return true;
    }
    var phead: u32 = 0;
    let existing .= st.ctx_site_paths.get(wkey);
    if existing { let h: u32 = existing; phead = h; }
    if listAdd(st, phead, path_id) {
        st.ctx_site_paths.insert(wkey, phead);
        if listLen(st, phead) > MAX_PATHS_PER_SITE {
            st.ctx_widened_sites.insert(wkey, true);
            return true;
        }
    }
    return false;
}

// Recompute `Summary(ctx_id)` from `ctx`'s converged graph; returns true if Summary grew or widened.
fn publishSummary(st: Analyzer&, ctx_id: u32, force_notify: bool) -> bool {
    var newly_widened: u32 = 0;
    var seeds: u32 = 0;
    let _ = listUnionHead(st, seeds, st.ctxs[ctx_id].ret_pts_head);
    var ec = st.ctxs[ctx_id].base_edges_head;
    while ec != 0 {
        let en = st.edge_nodes[ec];
        if isPreExisting(st, ctx_id, en.edge.src) { let _ = listAdd(st, seeds, en.edge.src); }
        if isPreExisting(st, ctx_id, en.edge.dst) { let _ = listAdd(st, seeds, en.edge.dst); }
        ec = en.next;
    }
    ec = st.ctxs[ctx_id].written_edges_head;
    while ec != 0 {
        let en = st.edge_nodes[ec];
        if isPreExisting(st, ctx_id, en.edge.src) { let _ = listAdd(st, seeds, en.edge.src); }
        ec = en.next;
    }
    let def = st.fn_defs[st.ctxs[ctx_id].fn_id];
    for pi in 0..(def.param_len as i64) {
        let pb = st.fn_bindings[(def.param_start as i64) + pi];
        let _ = listUnionHead(st, seeds, getBindingHead(st, ctx_id, pb));
    }
    for ci in 0..(def.capture_len as i64) {
        let cb = st.fn_bindings[(def.capture_start as i64) + ci];
        let _ = listUnionHead(st, seeds, getBindingHead(st, ctx_id, cb));
    }
    var escaped_set: dictionary<u32, bool> = dictionary<u32, bool>{};
    var escaped_vec: u32[>..] = [];
    reachIntoSet(st, ctx_id, seeds, escaped_set, escaped_vec);

    // Pass 1: detect any newly triggered widening latches.
    var rc = st.ctxs[ctx_id].ret_pts_head;
    while rc != 0 {
        let s = st.u32_nodes[rc].val;
        let rn = st.u32_nodes[rc].next;
        let ps = piStatic(st, ctx_id, s);
        if checkWideningLatch(st, ctx_id, ps) {
            let psk = st.syms[ps];
            var os: u32 = psk.b;
            if psk.kind == SYM_SUM_FN { os = st.syms[psk.b].b; }
            let _ = listAdd(st, newly_widened, os);
        }
        rc = rn;
    }
    ec = st.ctxs[ctx_id].written_edges_head;
    while ec != 0 {
        let e = st.edge_nodes[ec].edge;
        let enext = st.edge_nodes[ec].next;
        if escaped_set.contains(e.src) {
            let pu = piStatic(st, ctx_id, e.src);
            let pv = piStatic(st, ctx_id, e.dst);
            if checkWideningLatch(st, ctx_id, pu) {
                let k = st.syms[pu];
                if k.kind == SYM_SUM_ALLOC { let _ = listAdd(st, newly_widened, k.b); }
                else if k.kind == SYM_SUM_FN && st.syms[k.b].kind == SYM_SUM_ALLOC { let _ = listAdd(st, newly_widened, st.syms[k.b].b); }
            }
            if checkWideningLatch(st, ctx_id, pv) {
                let k = st.syms[pv];
                if k.kind == SYM_SUM_ALLOC { let _ = listAdd(st, newly_widened, k.b); }
                else if k.kind == SYM_SUM_FN && st.syms[k.b].kind == SYM_SUM_ALLOC { let _ = listAdd(st, newly_widened, st.syms[k.b].b); }
            }
        }
        ec = enext;
    }

    // Pass 2: project ret_pts, edges, mutates, reads_globals using updated widened latches.
    var new_ret: u32 = 0;
    rc = st.ctxs[ctx_id].ret_pts_head;
    while rc != 0 {
        let s = st.u32_nodes[rc].val;
        let rn = st.u32_nodes[rc].next;
        let _ = listAdd(st, new_ret, piStatic(st, ctx_id, s));
        rc = rn;
    }
    var new_edges: u32 = 0;
    var new_edge_set: dictionary<Edge, bool> = dictionary<Edge, bool>{};
    var new_edge_count: i64 = 0;
    ec = st.ctxs[ctx_id].written_edges_head;
    while ec != 0 {
        let e = st.edge_nodes[ec].edge;
        let enext = st.edge_nodes[ec].next;
        if escaped_set.contains(e.src) {
            let pe = Edge { src: piStatic(st, ctx_id, e.src), lbl: e.lbl, dst: piStatic(st, ctx_id, e.dst) };
            if !new_edge_set.contains(pe) {
                new_edge_set.insert(pe, true);
                new_edge_count += 1;
                let idx = st.edge_nodes.len as u32;
                st.edge_nodes.push(EdgeNode { edge: pe, next: new_edges });
                new_edges = idx;
            }
        }
        ec = enext;
    }
    var new_mut: u32 = 0;
    var mc = st.ctxs[ctx_id].mutated_head;
    while mc != 0 {
        let s = st.u32_nodes[mc].val;
        let mn = st.u32_nodes[mc].next;
        if isPreExisting(st, ctx_id, s) || st.syms[s].kind == SYM_GLOBAL { let _ = listAdd(st, new_mut, s); }
        mc = mn;
    }
    var new_reads: u32 = 0;
    let _ = listUnionHead(st, new_reads, st.ctxs[ctx_id].reads_globals_head);

    var changed = newly_widened != 0;
    if !changed {
        var edges_same = true;
        var old_edge_count: i64 = 0;
        var oec = st.ctxs[ctx_id].sum_edges_head;
        while oec != 0 {
            let oen = st.edge_nodes[oec];
            old_edge_count += 1;
            if !new_edge_set.contains(oen.edge) { edges_same = false; break; }
            oec = oen.next;
        }
        if edges_same && old_edge_count != new_edge_count { edges_same = false; }
        if !edges_same ||
           !listEqual(st, new_ret, st.ctxs[ctx_id].sum_ret_head) ||
           !listEqual(st, new_mut, st.ctxs[ctx_id].sum_mut_head) ||
           !listEqual(st, new_reads, st.ctxs[ctx_id].sum_reads_head) {
            changed = true;
        }
    }
    if changed {
        st.ctxs[ctx_id].sum_ret_head = new_ret;
        st.ctxs[ctx_id].sum_edges_head = new_edges;
        st.ctxs[ctx_id].sum_mut_head = new_mut;
        st.ctxs[ctx_id].sum_reads_head = new_reads;
    }

    var caller_ctxs: u32[>..] = [];
    var caller_sites: u32[>..] = [];
    var cc = st.ctxs[ctx_id].callers_head;
    while cc != 0 {
        let cn = st.caller_nodes[cc];
        caller_ctxs.push(cn.caller_ctx);
        caller_sites.push(cn.call_site);
        cc = cn.next;
    }
    if newly_widened != 0 {
        var wc = newly_widened;
        while wc != 0 {
            let os = st.u32_nodes[wc].val;
            let wn = st.u32_nodes[wc].next;
            for ci in 0..caller_ctxs.len {
                remapCallerForWidenedSite(st, caller_ctxs[ci], caller_sites[ci], os);
            }
            wc = wn;
        }
    }
    if changed || force_notify {
        for cctx in caller_ctxs { markCtxDirty(st, cctx); }
    }
    return changed;
}

// ---- Caller-Side Summary Instantiation `σ*` (§2.5) — zero resizable locals ----

recursive fn applySigmaStar(
    st: Analyzer&,
    caller_ctx: u32,
    call_site: u32,
    arg_range: Range,
    cap_range: Range,
    h_range: Range,
    sum_sym: u32
) -> u32 {
    let sk = st.syms[sum_sym];
    if sk.kind == SYM_EMPTY_ENV || sk.kind == SYM_GLOBAL || sk.kind == SYM_OP_VAL || sk.kind == SYM_CTOR_FN || sk.kind == SYM_PRIM_FN {
        return listSingle(st, sum_sym);
    }
    if sk.kind == SYM_PARAM {
        if (sk.a as i64) < arg_range.len { return st.head_stack[arg_range.start + (sk.a as i64)]; }
        return 0;
    }
    if sk.kind == SYM_CAPTURE {
        if (sk.a as i64) < cap_range.len { return st.head_stack[cap_range.start + (sk.a as i64)]; }
        return 0;
    }
    if sk.kind == SYM_PARAM_ENV {
        var src_head: u32 = 0;
        if sk.a >= 2000 {
            var outer_head: u32 = 0;
            var nested_ci: u32 = 0;
            if sk.a >= 100000 {
                let k = ((sk.a - 100000) / 64) as i64;
                nested_ci = (sk.a - 100000) % 64;
                if k < cap_range.len { outer_head = st.head_stack[cap_range.start + k]; }
            } else {
                let j = ((sk.a - 2000) / 64) as i64;
                nested_ci = (sk.a - 2000) % 64;
                if j < arg_range.len { outer_head = st.head_stack[arg_range.start + j]; }
            }
            var outer_envs: u32 = 0;
            var oc = outer_head;
            while oc != 0 {
                let os = st.u32_nodes[oc].val;
                let on = st.u32_nodes[oc].next;
                let osk = st.syms[os];
                if osk.kind == SYM_FN_VAL { let _ = listAdd(st, outer_envs, osk.b); }
                oc = on;
            }
            src_head = stepCaptureHead(st, caller_ctx, outer_envs, nested_ci);
        } else if sk.a >= 1000 {
            let ci = (sk.a - 1000) as i64;
            if ci < cap_range.len { src_head = st.head_stack[cap_range.start + ci]; }
        } else if (sk.a as i64) < arg_range.len {
            src_head = st.head_stack[arg_range.start + (sk.a as i64)];
        }
        var out: u32 = 0;
        var cur = src_head;
        while cur != 0 {
            let s = st.u32_nodes[cur].val;
            let nxt = st.u32_nodes[cur].next;
            let ssk = st.syms[s];
            if ssk.kind == SYM_FN_VAL && ssk.a == sk.b { let _ = listAdd(st, out, ssk.b); }
            cur = nxt;
        }
        return out;
    }
    if sk.kind == SYM_CAP_NODE {
        let envs = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, symParamEnv(st, sk.a, sk.b));
        return stepCaptureHead(st, caller_ctx, envs, sk.c);
    }
    if sk.kind == SYM_HANDLER_CAP {
        if (sk.a as i64) < h_range.len {
            let frame = st.handler_stack[h_range.start + (sk.a as i64)];
            if frame.kind == HANDLER_CLOSURE {
                let env_h = listSingle(st, frame.env_sym);
                return stepCaptureHead(st, caller_ctx, env_h, sk.b);
            }
        }
        return 0;
    }
    if sk.kind == SYM_HANDLER_CELL {
        if (sk.a as i64) < h_range.len {
            let frame = st.handler_stack[h_range.start + (sk.a as i64)];
            if frame.has_cell { return listSingle(st, frame.cell_sym); }
        }
        return 0;
    }
    if sk.kind == SYM_CHILD {
        let base = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, sk.a);
        return reachStrictHead(st, caller_ctx, base);
    }
    if sk.kind == SYM_SUM_ALLOC {
        return listSingle(st, symCalleeFresh(st, call_site, sk.a, sk.b));
    }
    if sk.kind == SYM_SUM_FN {
        let envs = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, sk.b);
        var out: u32 = 0;
        var cur = envs;
        while cur != 0 {
            let env_s = st.u32_nodes[cur].val;
            let nxt = st.u32_nodes[cur].next;
            let _ = listAdd(st, out, symFnVal(st, sk.a, env_s, sk.sub));
            cur = nxt;
        }
        return out;
    }
    return listSingle(st, sum_sym);
}

fn pushUniqueCallableSpec(specs: CallableSpec[>..]& , cs: CallableSpec) {
    for prev in specs {
        if prev.slot == cs.slot && prev.tag_kind == cs.tag_kind && prev.applied == cs.applied && prev.target_a == cs.target_a && prev.target_b == cs.target_b { return; }
    }
    specs.push(cs);
}

fn inspectNestedCallableCaptures(st: Analyzer&, caller_ctx: u32, base_slot: u32, target_fn: u32, env_sym: u32, applied: u8, specs: CallableSpec[>..]&) {
    var own_caps: i64 = 0;
    if st.fn_defs[target_fn].kind == FN_CLOSURE { own_caps = st.fn_defs[target_fn].capture_len as i64; }
    let total_caps = own_caps + (applied as i64);
    let env_h = listSingle(st, env_sym);
    for ci in 0..total_caps {
        if ci >= 64 { break; }
        let cap_head = stepCaptureHead(st, caller_ctx, env_h, ci as u32);
        if cap_head == 0 { continue; }
        var all_callable = true;
        var cur = cap_head;
        while cur != 0 {
            let k = st.syms[st.u32_nodes[cur].val].kind;
            if k != SYM_FN_VAL && k != SYM_OP_VAL && k != SYM_CTOR_FN && k != SYM_PRIM_FN { all_callable = false; break; }
            cur = st.u32_nodes[cur].next;
        }
        if !all_callable { continue; }
        var nslot: u32 = 2000 + base_slot * 64 + (ci as u32);
        if base_slot >= 1000 { nslot = 100000 + (base_slot - 1000) * 64 + (ci as u32); }
        cur = cap_head;
        while cur != 0 {
            let nsk = st.syms[st.u32_nodes[cur].val];
            var ncs = CallableSpec { slot: nslot };
            if nsk.kind == SYM_FN_VAL { ncs.tag_kind = 0; ncs.applied = nsk.sub; ncs.target_a = nsk.a; }
            else if nsk.kind == SYM_OP_VAL { ncs.tag_kind = 1; ncs.target_a = nsk.a; }
            else if nsk.kind == SYM_CTOR_FN { ncs.tag_kind = 2; ncs.target_a = nsk.a; ncs.target_b = nsk.b; }
            else if nsk.kind == SYM_PRIM_FN { ncs.tag_kind = 3; ncs.target_a = nsk.a; ncs.target_b = nsk.b; }
            pushUniqueCallableSpec(specs, ncs);
            cur = st.u32_nodes[cur].next;
        }
    }
}

fn buildCallableSpecsRange(st: Analyzer&, caller_ctx: u32, arg_range: Range, cap_range: Range) -> CallableSpec[>..] {
    var specs: CallableSpec[>..] = [];
    for j in 0..arg_range.len {
        let head = st.head_stack[arg_range.start + j];
        if head == 0 { continue; }
        var all_callable = true;
        var cur = head;
        while cur != 0 {
            let k = st.syms[st.u32_nodes[cur].val].kind;
            if k != SYM_FN_VAL && k != SYM_OP_VAL && k != SYM_CTOR_FN && k != SYM_PRIM_FN { all_callable = false; break; }
            cur = st.u32_nodes[cur].next;
        }
        if !all_callable { continue; }
        cur = head;
        while cur != 0 {
            let sk = st.syms[st.u32_nodes[cur].val];
            var cs = CallableSpec { slot: j as u32 };
            if sk.kind == SYM_FN_VAL { cs.tag_kind = 0; cs.applied = sk.sub; cs.target_a = sk.a; }
            else if sk.kind == SYM_OP_VAL { cs.tag_kind = 1; cs.target_a = sk.a; }
            else if sk.kind == SYM_CTOR_FN { cs.tag_kind = 2; cs.target_a = sk.a; cs.target_b = sk.b; }
            else if sk.kind == SYM_PRIM_FN { cs.tag_kind = 3; cs.target_a = sk.a; cs.target_b = sk.b; }
            pushUniqueCallableSpec(specs, cs);
            if sk.kind == SYM_FN_VAL {
                inspectNestedCallableCaptures(st, caller_ctx, j as u32, sk.a, sk.b, sk.sub, specs);
            }
            cur = st.u32_nodes[cur].next;
        }
    }
    for ci in 0..cap_range.len {
        let head = st.head_stack[cap_range.start + ci];
        if head == 0 { continue; }
        var all_callable = true;
        var cur = head;
        while cur != 0 {
            let k = st.syms[st.u32_nodes[cur].val].kind;
            if k != SYM_FN_VAL && k != SYM_OP_VAL && k != SYM_CTOR_FN && k != SYM_PRIM_FN { all_callable = false; break; }
            cur = st.u32_nodes[cur].next;
        }
        if !all_callable { continue; }
        cur = head;
        while cur != 0 {
            let sk = st.syms[st.u32_nodes[cur].val];
            let cslot = 1000 + (ci as u32);
            var cs = CallableSpec { slot: cslot };
            if sk.kind == SYM_FN_VAL { cs.tag_kind = 0; cs.applied = sk.sub; cs.target_a = sk.a; }
            else if sk.kind == SYM_OP_VAL { cs.tag_kind = 1; cs.target_a = sk.a; }
            else if sk.kind == SYM_CTOR_FN { cs.tag_kind = 2; cs.target_a = sk.a; cs.target_b = sk.b; }
            else if sk.kind == SYM_PRIM_FN { cs.tag_kind = 3; cs.target_a = sk.a; cs.target_b = sk.b; }
            pushUniqueCallableSpec(specs, cs);
            if sk.kind == SYM_FN_VAL {
                inspectNestedCallableCaptures(st, caller_ctx, cslot, sk.a, sk.b, sk.sub, specs);
            }
            cur = st.u32_nodes[cur].next;
        }
    }
    return specs;
}

fn buildHandlerSpecsRange(st: const Analyzer&, h_range: Range) -> HandlerSpec[>..] {
    var out: HandlerSpec[>..] = [];
    for hi in 0..h_range.len {
        let f = st.handler_stack[h_range.start + hi];
        out.push(HandlerSpec { op_key: f.op_key, kind: f.kind, fn_id: f.fn_id, applied: f.applied, cap_count: f.cap_count });
    }
    return out;
}

fn invokeSummary(
    st: Analyzer&,
    caller_ctx: u32,
    target_fn: u32,
    call_site: u32,
    arg_range: Range,
    cap_range: Range,
    h_range: Range,
    err_unit: u32,
    err_span: blot_check_core::Span,
    changed: bool&
) -> u32 {
    let cspecs = buildCallableSpecsRange(st, caller_ctx, arg_range, cap_range);
    let hspecs = buildHandlerSpecsRange(st, h_range);
    let callee_ctx, ok = getOrCreateCtx(st, target_fn, cspecs[..], hspecs[..], err_unit, err_span);
    if !ok {
        st.ctxs[caller_ctx].unresolved_error = true;
        st.ctxs[caller_ctx].error_unit = err_unit;
        st.ctxs[caller_ctx].error_span = err_span;
        st.ctxs[caller_ctx].error_code = blot_check_diagnostic_code::Code.purity_limit;
        st.ctxs[caller_ctx].error_msg = "purity analyzer context/handler limit exceeded";
        return 0;
    }
    registerCaller(st, callee_ctx, caller_ctx, call_site);
    if st.ctxs[callee_ctx].unresolved_error && !st.ctxs[caller_ctx].unresolved_error {
        st.ctxs[caller_ctx].unresolved_error = true;
        st.ctxs[caller_ctx].error_unit = st.ctxs[callee_ctx].error_unit;
        st.ctxs[caller_ctx].error_span = st.ctxs[callee_ctx].error_span;
        st.ctxs[caller_ctx].error_code = st.ctxs[callee_ctx].error_code;
        st.ctxs[caller_ctx].error_msg = st.ctxs[callee_ctx].error_msg;
    }
    var ret_head: u32 = 0;
    var rc = st.ctxs[callee_ctx].sum_ret_head;
    while rc != 0 {
        let r = st.u32_nodes[rc].val;
        let rn = st.u32_nodes[rc].next;
        let mapped = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, r);
        let _ = listUnionHead(st, ret_head, mapped);
        rc = rn;
    }
    var ec = st.ctxs[callee_ctx].sum_edges_head;
    while ec != 0 {
        let e = st.edge_nodes[ec].edge;
        let en = st.edge_nodes[ec].next;
        let srcs = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, e.src);
        let dsts = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, e.dst);
        if addWrittenEdgesHeads(st, caller_ctx, srcs, e.lbl, dsts) { changed = true; }
        ec = en;
    }
    var mc = st.ctxs[callee_ctx].sum_mut_head;
    while mc != 0 {
        let m_sym = st.u32_nodes[mc].val;
        let mn = st.u32_nodes[mc].next;
        let mapped = applySigmaStar(st, caller_ctx, call_site, arg_range, cap_range, h_range, m_sym);
        if listUnionHead(st, st.ctxs[caller_ctx].mutated_head, mapped) { changed = true; }
        mc = mn;
    }
    if listUnionHead(st, st.ctxs[caller_ctx].reads_globals_head, st.ctxs[callee_ctx].sum_reads_head) { changed = true; }
    return ret_head;
}

// ---- Core Body Evaluator (All Admitted Ops & 8 Core PatternTags, §2.5) ----

root struct EvalEnv {
    ctx_id: u32 = 0,
    unit: u32 = 0,
    root: u32 = 0,
    changed: bool = false,
    handlers_base: i64 = 0,
    active_with_cells: dictionary<u32, u32> = dictionary<u32, u32>{},
}

fn recordUnresolved(st: Analyzer&, env: EvalEnv&, unit: u32, span: blot_check_core::Span, code: Code, msg: Chars) {
    if !st.ctxs[env.ctx_id].unresolved_error {
        st.ctxs[env.ctx_id].unresolved_error = true;
        st.ctxs[env.ctx_id].error_unit = unit;
        st.ctxs[env.ctx_id].error_span = span;
        st.ctxs[env.ctx_id].error_code = code;
        st.ctxs[env.ctx_id].error_msg = msg;
    }
}

fn bindLocal(st: Analyzer&, env: EvalEnv&, binding: u32, val_head: u32) {
    if unionBindingHead(st, env.ctx_id, binding, val_head) { env.changed = true; }
}

// Shared recursive 8-case Core PatternTag binder (§2.5) — zero resizable locals!
recursive fn bindPattern(st: Analyzer&, units: const Module[:], env: EvalEnv&, pid: u32, val_head: u32, depth: i64) {
    if pid == 0 || depth > 128 { return; }
    let m .= units[env.unit - 1];
    if (pid as i64) >= m.patterns.len { return; }
    let pat = m.pattern(pid);
    match pat.tag {
        wildcard, constant, invalid => {},
        value => {
            let _ = evalNode(st, units, env, pat.a, depth + 1);
        },
        bind => {
            if val_head != 0 && !isPureScalarCached(st, units, env.unit, pat.ty) {
                bindLocal(st, env, pat.a, val_head);
            }
        },
        product => {
            let kids = m.patternChildren(pid);
            let pty = m.types.node(pat.ty);
            if pty.tag == blot_check_types::Tag.record {
                for i in 0..kids.len {
                    if i < (pty.b as i64) {
                        let rf = m.types.recordField(pty, i);
                        let sp = m.fieldSpelling(rf.name);
                        if sp.present {
                            let lbl = internFieldLabel(st, sp.value);
                            let fpts = stepFieldHead(st, env.ctx_id, val_head, lbl);
                            bindPattern(st, units, env, kids[i], fpts, depth + 1);
                        }
                    }
                }
            } else if pty.tag == blot_check_types::Tag.product {
                for i in 0..kids.len {
                    let tpts = stepTupleHead(st, env.ctx_id, val_head, i as u32);
                    bindPattern(st, units, env, kids[i], tpts, depth + 1);
                }
            }
        },
        constructor => {
            if pat.b != 0 {
                let cpts = stepCtorHead(st, env.ctx_id, val_head);
                bindPattern(st, units, env, pat.b, cpts, depth + 1);
            }
        },
        record_payload => {
            let storage = m.types.node(pat.ty);
            if storage.tag != blot_check_types::Tag.record || storage.b == 0 { return; }
            if storage.b == 1 {
                let rf = m.types.recordField(storage, 0);
                let sp = m.fieldSpelling(rf.name);
                if sp.present {
                    let lbl = internFieldLabel(st, sp.value);
                    let fpts = stepFieldHead(st, env.ctx_id, val_head, lbl);
                    bindPattern(st, units, env, pat.b, fpts, depth + 1);
                }
                return;
            }
            let inner = m.pattern(pat.b);
            if inner.tag == blot_check_core::PatternTag.product {
                let kids = m.patternChildren(pat.b);
                for i in 0..(storage.b as i64) {
                    if i >= kids.len { break; }
                    let rf = m.types.recordField(storage, i);
                    let sp = m.fieldSpelling(rf.name);
                    if sp.present {
                        let lbl = internFieldLabel(st, sp.value);
                        let fpts = stepFieldHead(st, env.ctx_id, val_head, lbl);
                        bindPattern(st, units, env, kids[i], fpts, depth + 1);
                    }
                }
            } else {
                let fresh = symFresh(st, env.unit, pid, 5000);
                for i in 0..(storage.b as i64) {
                    let rf = m.types.recordField(storage, i);
                    let sp = m.fieldSpelling(rf.name);
                    if sp.present {
                        let lbl = internFieldLabel(st, sp.value);
                        let fpts = stepFieldHead(st, env.ctx_id, val_head, lbl);
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, fresh, LBL_TUPLE_BASE + (i as u32), fpts) { env.changed = true; }
                    }
                }
                bindPattern(st, units, env, pat.b, listSingle(st, fresh), depth + 1);
            }
        },
    }
}

// Shared positional/record constructor lowering (§2.5).
fn evalConstructValue(
    st: Analyzer&,
    units: const Module[:],
    env: EvalEnv&,
    site_node: u32,
    ctor_unit: u32,
    ctor_idx: u32,
    payload_head: u32,
    is_positional: bool,
    payload_is_product_node: bool,
    product_range: Range
) -> u32 {
    let cm .= units[ctor_unit - 1];
    let ctor = cm.constructor(ctor_idx);
    let fresh = symFresh(st, env.unit, site_node, 0);
    if ctor.payload == 0 {
        return listSingle(st, fresh);
    }
    let pnode = cm.types.node(ctor.payload);
    let nom = cm.nominal(ctor.nominal);
    if is_positional && !nom.is_opaque && pnode.tag == blot_check_types::Tag.record && pnode.b > 0 {
        let rec_fresh = symFresh(st, env.unit, site_node, 1);
        if addWrittenEdge(st, env.ctx_id, fresh, LBL_CTOR_PAYLOAD, rec_fresh) { env.changed = true; }
        if pnode.b == 1 {
            let rf = cm.types.recordField(pnode, 0);
            let sp = cm.fieldSpelling(rf.name);
            if sp.present {
                let lbl = internFieldLabel(st, sp.value);
                if addWrittenEdgesSingleSrc(st, env.ctx_id, rec_fresh, lbl, payload_head) { env.changed = true; }
            }
        } else {
            for i in 0..(pnode.b as i64) {
                let rf = cm.types.recordField(pnode, i);
                let sp = cm.fieldSpelling(rf.name);
                if sp.present {
                    let lbl = internFieldLabel(st, sp.value);
                    if payload_is_product_node && i < product_range.len {
                        let c_h = st.head_stack[product_range.start + i];
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, rec_fresh, lbl, c_h) { env.changed = true; }
                    } else {
                        let tpts = stepTupleHead(st, env.ctx_id, payload_head, i as u32);
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, rec_fresh, lbl, tpts) { env.changed = true; }
                    }
                }
            }
        }
        return listSingle(st, fresh);
    }
    if addWrittenEdgesSingleSrc(st, env.ctx_id, fresh, LBL_CTOR_PAYLOAD, payload_head) { env.changed = true; }
    return listSingle(st, fresh);
}

// Check whether `project` on `recv_ty` accesses a data field (plain record or
// single-constructor nominal record payload) rather than an associated method.
fn isDataFieldProjection(units: const Module[:], m: const Module&, recv_ty: TId, field_name: Chars) -> bool {
    var cur = recv_ty;
    for _ in 0..8 {
        if (cur as i64) >= m.types.nodes.len { return false; }
        let n = m.types.node(cur);
        if n.tag == blot_check_types::Tag.usage || n.tag == blot_check_types::Tag.forall { cur = n.a; continue; }
        let sh = blot_check_storage_types::sharedInner(m.types, cur);
        if sh.present { cur = sh.value; continue; }
        break;
    }
    if (cur as i64) >= m.types.nodes.len { return false; }
    let rn = m.types.node(cur);
    if rn.tag == blot_check_types::Tag.record {
        for fi in 0..(rn.b as i64) {
            let rf = m.types.recordField(rn, fi);
            let sp = m.fieldSpelling(rf.name);
            if sp.present && sp.value == field_name { return true; }
        }
        return false;
    }
    if rn.tag == blot_check_types::Tag.nominal && !blot_check_storage_types::identity(rn.a, rn.b).present && hasUnit(units, rn.a) {
        let dm .= units[rn.a - 1];
        let want = Identity { rn.a, rn.b };
        var ctor_count: i64 = 0;
        var matched = false;
        for ctor in dm.constructors {
            if dm.nominal(ctor.nominal).identity != want { continue; }
            ctor_count += 1;
            if ctor_count > 1 { return false; }
            if ctor.payload != 0 && (ctor.payload as i64) < dm.types.nodes.len {
                let pn = dm.types.node(ctor.payload);
                if pn.tag == blot_check_types::Tag.record {
                    for fi in 0..(pn.b as i64) {
                        let rf = dm.types.recordField(pn, fi);
                        let sp = dm.fieldSpelling(rf.name);
                        if sp.present && sp.value == field_name { matched = true; break; }
                    }
                }
            }
        }
        return ctor_count == 1 && matched;
    }
    return false;
}

fn ensureAssocIndex(st: Analyzer&, units: const Module[:]) {
    if st.assoc_index_built { return; }
    st.assoc_index_built = true;
    for u_idx in 0..units.len {
        let um .= units[u_idx];
        for assoc in um.associated {
            let res = blot_check_wire_schema::resolveBindingTarget(units, um.unit, assoc.target);
            if res.unit == 0 || res.binding == 0 { continue; }
            if assoc.operator != blot_check_types::Operator.none {
                let idx = st.assoc_entries.len as u32;
                st.assoc_entries.push(AssocEntry { identity: assoc.identity, op: assoc.operator, target: res, next: st.assoc_op_head });
                st.assoc_op_head = idx;
            }
            let sp = um.fieldSpelling(assoc.member);
            if sp.present {
                let lbl = internFieldLabel(st, sp.value);
                var prev: u32 = 0;
                let opt .= st.assoc_by_name.get(lbl);
                if opt { let h: u32 = opt; prev = h; }
                let idx = st.assoc_entries.len as u32;
                st.assoc_entries.push(AssocEntry { identity: assoc.identity, op: blot_check_types::Operator.none, target: res, next: prev });
                st.assoc_by_name.insert(lbl, idx);
            }
        }
        for impl_ in um.implementations {
            var has_head_id = false;
            var is_prim_head = false;
            var head_id = Identity { 0, 0 };
            let head_list = um.types.list(impl_.head);
            if head_list.len != 0 {
                var hcur = head_list[0];
                for _ in 0..8 {
                    if (hcur as i64) >= um.types.nodes.len { break; }
                    let hn = um.types.node(hcur);
                    if hn.tag == blot_check_types::Tag.usage || hn.tag == blot_check_types::Tag.forall { hcur = hn.a; continue; }
                    break;
                }
                if (hcur as i64) < um.types.nodes.len {
                    let hn = um.types.node(hcur);
                    if hn.tag == blot_check_types::Tag.nominal {
                        has_head_id = true;
                        head_id = Identity { hn.a, hn.b };
                    } else if blot_check_storage_types::isArray(um.types, hcur) {
                        has_head_id = true;
                        head_id = Identity { 0, 0xffffffff };
                    } else if hn.tag == blot_check_types::Tag.unsigned32 || hn.tag == blot_check_types::Tag.floating32 || hn.tag == blot_check_types::Tag.boolean {
                        is_prim_head = true;
                    }
                }
            }
            let ckey = ((impl_.contract.unit as u64) << 32) | (impl_.contract.decl as u64);
            for mem in um.implementation_members[impl_.members.start..impl_.members.start + impl_.members.len] {
                if mem.kind != blot_reuse_principal_interface::ImplementationMemberKind.value { continue; }
                let msp = um.fieldSpelling(mem.name);
                if !msp.present { continue; }
                let res = blot_check_wire_schema::resolveBindingTarget(units, um.unit, BindingRef { unit: mem.target.unit, binding: mem.target.binding });
                if res.unit == 0 || res.binding == 0 { continue; }
                let lbl = internFieldLabel(st, msp.value);
                var prev_n: u32 = 0;
                let nopt .= st.impl_by_name.get(lbl);
                if nopt { let h: u32 = nopt; prev_n = h; }
                var prev_c: u32 = 0;
                let copt .= st.impl_by_contract.get(ckey);
                if copt { let h: u32 = copt; prev_c = h; }
                let idx = st.impl_entries.len as u32;
                st.impl_entries.push(ImplMemEntry {
                    contract: impl_.contract,
                    has_head_id: has_head_id,
                    is_prim_head: is_prim_head,
                    head_id: head_id,
                    name_lbl: lbl,
                    target: res,
                    next_by_name: prev_n,
                    next_by_contract: prev_c,
                });
                st.impl_by_name.insert(lbl, idx);
                st.impl_by_contract.insert(ckey, idx);
            }
        }
    }
}

// Push matching associated/trait method targets onto `st.target_stack`; returns Range.
fn pushAssociatedMethodTargets(st: Analyzer&, units: const Module[:], m: const Module&, recv_ty: TId, field_name: Chars, op: blot_check_types::Operator) -> Range {
    ensureAssocIndex(st, units);
    let tmark = st.target_stack.len;
    var cur = recv_ty;
    for _ in 0..8 {
        if (cur as i64) >= m.types.nodes.len { break; }
        let n = m.types.node(cur);
        if n.tag == blot_check_types::Tag.usage || n.tag == blot_check_types::Tag.forall { cur = n.a; continue; }
        let sh = blot_check_storage_types::sharedInner(m.types, cur);
        if sh.present { cur = sh.value; continue; }
        break;
    }
    let rn = m.types.node(cur);
    var has_id = false;
    var ident = Identity { 0, 0 };
    var alt_ident = Identity { 0, 0 };
    var has_alt = false;
    if rn.tag == blot_check_types::Tag.nominal && !blot_check_storage_types::identity(rn.a, rn.b).present {
        has_id = true;
        ident = Identity { rn.a, rn.b };
    } else if rn.tag == blot_check_types::Tag.nominal && rn.a == 0xffffffff {
        has_id = true;
        ident = Identity { rn.a, rn.b };
        has_alt = true;
        alt_ident = Identity { 0, 0xffffffff };
    } else if blot_check_storage_types::isArray(m.types, cur) {
        has_id = true;
        ident = Identity { 0, 0xffffffff };
    }
    if op != blot_check_types::Operator.none {
        var ac = st.assoc_op_head;
        while ac != 0 {
            let e = st.assoc_entries[ac];
            if e.op == op && (!has_id || e.identity == ident || (has_alt && e.identity == alt_ident)) {
                var dup = false;
                for pi in tmark..st.target_stack.len { if st.target_stack[pi] == e.target { dup = true; break; } }
                if !dup { st.target_stack.push(e.target); }
            }
            ac = e.next;
        }
        return Range { start: tmark, len: st.target_stack.len - tmark };
    }
    let lbl = internFieldLabel(st, field_name);
    let aopt .= st.assoc_by_name.get(lbl);
    if aopt {
        var ac: u32 = aopt;
        while ac != 0 {
            let e = st.assoc_entries[ac];
            if !has_id || e.identity == ident || (has_alt && e.identity == alt_ident) {
                var dup = false;
                for pi in tmark..st.target_stack.len { if st.target_stack[pi] == e.target { dup = true; break; } }
                if !dup { st.target_stack.push(e.target); }
            }
            ac = e.next;
        }
    }
    if st.target_stack.len == tmark {
        let iopt .= st.impl_by_name.get(lbl);
        if iopt {
            var ic: u32 = iopt;
            while ic != 0 {
                let e = st.impl_entries[ic];
                var ok = true;
                if has_id {
                    if e.is_prim_head { ok = false; }
                    else if e.has_head_id && e.head_id != ident && (!has_alt || e.head_id != alt_ident) { ok = false; }
                }
                if ok {
                    var dup = false;
                    for pi in tmark..st.target_stack.len { if st.target_stack[pi] == e.target { dup = true; break; } }
                    if !dup { st.target_stack.push(e.target); }
                }
                ic = e.next_by_name;
            }
        }
    }
    return Range { start: tmark, len: st.target_stack.len - tmark };
}

// Apply a single callable `callee_head` to `arg_head` at node `id` (§2.5) — zero resizable locals!
recursive fn evalApplyValues(st: Analyzer&, units: const Module[:], env: EvalEnv&, id: u32, sub_site: u32, callee_head: u32, arg_head: u32, depth: i64) -> u32 {
    let m .= units[env.unit - 1];
    let span = m.span(id);
    if callee_head == 0 {
        recordUnresolved(st, env, env.unit, span, blot_check_diagnostic_code::Code.purity_limit, "cannot statically resolve indirect call target in read-only region");
        return 0;
    }
    var out: u32 = 0;
    let cur_hrange = Range { start: env.handlers_base, len: st.handler_stack.len - env.handlers_base };
    var cc = callee_head;
    while cc != 0 {
        let cv = st.u32_nodes[cc].val;
        let cn = st.u32_nodes[cc].next;
        let sk = st.syms[cv];
        if sk.kind == SYM_FN_VAL {
            let target_fn = sk.a;
            let env_sym = sk.b;
            let applied = sk.sub as i64;
            let tdef = st.fn_defs[target_fn];
            let arity = tdef.param_len as i64;
            var own_caps: i64 = 0;
            if tdef.kind == FN_CLOSURE { own_caps = tdef.capture_len as i64; }
            if applied + 1 < arity {
                let next_env = symFresh(st, env.unit, id, 200 + sub_site);
                let env_h = listSingle(st, env_sym);
                for k in 0..(own_caps + applied) {
                    let prev_a = stepCaptureHead(st, env.ctx_id, env_h, k as u32);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, next_env, LBL_CAPTURE_BASE + (k as u32), prev_a) { env.changed = true; }
                }
                if addWrittenEdgesSingleSrc(st, env.ctx_id, next_env, LBL_CAPTURE_BASE + ((own_caps + applied) as u32), arg_head) { env.changed = true; }
                let _ = listAdd(st, out, symFnVal(st, target_fn, next_env, (applied + 1) as u8));
            } else {
                let hmark = st.head_stack.len;
                let env_h = listSingle(st, env_sym);
                for k in 0..applied {
                    st.head_stack.push(stepCaptureHead(st, env.ctx_id, env_h, (own_caps + k) as u32));
                }
                st.head_stack.push(arg_head);
                let ar = Range { start: hmark, len: st.head_stack.len - hmark };
                let cmark = st.head_stack.len;
                for ci in 0..own_caps {
                    st.head_stack.push(stepCaptureHead(st, env.ctx_id, env_h, ci as u32));
                }
                let cr = Range { start: cmark, len: st.head_stack.len - cmark };
                let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, sub_site);
                let r = invokeSummary(st, env.ctx_id, target_fn, cs_id, ar, cr, cur_hrange, env.unit, span, env.changed);
                st.head_stack.resize(hmark);
                let _ = listUnionHead(st, out, r);
            }
        } else if sk.kind == SYM_OP_VAL {
            let op_key = sk.a;
            var found_idx: i64 = -1;
            var hi = cur_hrange.len;
            while hi > 0 {
                hi -= 1;
                if st.handler_stack[cur_hrange.start + hi].op_key == op_key { found_idx = hi; break; }
            }
            if found_idx < 0 {
                let c_hstart = st.ctxs[env.ctx_id].hspec_start as i64;
                let c_hlen = st.ctxs[env.ctx_id].hspec_len as i64;
                var si = c_hlen;
                while si > 0 {
                    si -= 1;
                    let hs = st.ctx_hspecs[c_hstart + si];
                    if hs.op_key == op_key {
                        let pmark = st.handler_stack.len;
                        for pk in 0..si {
                            let phs = st.ctx_hspecs[c_hstart + pk];
                            var pf = ActiveHandlerFrame { op_key: phs.op_key, kind: phs.kind, fn_id: phs.fn_id, applied: phs.applied, cap_count: phs.cap_count };
                            if phs.kind == HANDLER_CLOSURE {
                                let penv = symFresh(st, env.unit, id, 600 + (pk as u32));
                                for ci in 0..(phs.cap_count as i64) {
                                    let hc = symHandlerCap(st, pk as u32, ci as u32);
                                    if addWrittenEdge(st, env.ctx_id, penv, LBL_CAPTURE_BASE + (ci as u32), hc) { env.changed = true; }
                                }
                                pf.env_sym = penv;
                            } else {
                                pf.cell_sym = symHandlerCell(st, pk as u32);
                                pf.has_cell = true;
                            }
                            st.handler_stack.push(pf);
                        }
                        let pr = Range { start: pmark, len: st.handler_stack.len - pmark };
                        if hs.kind == HANDLER_STATE_GET {
                            let cell_h = listSingle(st, symHandlerCell(st, si as u32));
                            let _ = listUnionHead(st, out, stepAnyHead(st, env.ctx_id, cell_h));
                        } else if hs.kind == HANDLER_STATE_SET {
                            let cell = symHandlerCell(st, si as u32);
                            if listAdd(st, st.ctxs[env.ctx_id].mutated_head, cell) { env.changed = true; }
                            if addWrittenEdgesSingleSrc(st, env.ctx_id, cell, LBL_ANY, arg_head) { env.changed = true; }
                        } else {
                            let hmark = st.head_stack.len;
                            st.head_stack.push(arg_head);
                            let ar = Range { start: hmark, len: 1 };
                            let cmark = st.head_stack.len;
                            for ci in 0..(hs.cap_count as i64) {
                                st.head_stack.push(listSingle(st, symHandlerCap(st, si as u32, ci as u32)));
                            }
                            let cr = Range { start: cmark, len: st.head_stack.len - cmark };
                            let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, 700 + sub_site);
                            let r = invokeSummary(st, env.ctx_id, hs.fn_id, cs_id, ar, cr, pr, env.unit, span, env.changed);
                            st.head_stack.resize(hmark);
                            let _ = listUnionHead(st, out, r);
                        }
                        st.handler_stack.resize(pmark);
                        found_idx = -2;
                        break;
                    }
                }
                if found_idx == -1 {
                    recordUnresolved(st, env, env.unit, span, blot_check_diagnostic_code::Code.purity_limit, "unhandled effect operation in purity analysis");
                }
            } else {
                let frame = st.handler_stack[cur_hrange.start + found_idx];
                // Predecessor handler stack `cur_hrange[0..found_idx]` (§2.5)!
                let pr = Range { start: cur_hrange.start, len: found_idx };
                if frame.kind == HANDLER_STATE_GET {
                    if frame.has_cell {
                        let cell_h = listSingle(st, frame.cell_sym);
                        let _ = listUnionHead(st, out, stepAnyHead(st, env.ctx_id, cell_h));
                    }
                } else if frame.kind == HANDLER_STATE_SET {
                    if frame.has_cell {
                        if listAdd(st, st.ctxs[env.ctx_id].mutated_head, frame.cell_sym) { env.changed = true; }
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, frame.cell_sym, LBL_ANY, arg_head) { env.changed = true; }
                    }
                } else {
                    let hmark = st.head_stack.len;
                    let env_h = listSingle(st, frame.env_sym);
                    for k in 0..(frame.applied as i64) {
                        st.head_stack.push(stepCaptureHead(st, env.ctx_id, env_h, k as u32));
                    }
                    st.head_stack.push(arg_head);
                    let ar = Range { start: hmark, len: st.head_stack.len - hmark };
                    let cmark = st.head_stack.len;
                    let tdef = st.fn_defs[frame.fn_id];
                    if tdef.kind == FN_CLOSURE {
                        for ci in 0..(tdef.capture_len as i64) {
                            st.head_stack.push(stepCaptureHead(st, env.ctx_id, env_h, ci as u32));
                        }
                    }
                    let cr = Range { start: cmark, len: st.head_stack.len - cmark };
                    let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, 800 + sub_site);
                    let r = invokeSummary(st, env.ctx_id, frame.fn_id, cs_id, ar, cr, pr, env.unit, span, env.changed);
                    st.head_stack.resize(hmark);
                    let _ = listUnionHead(st, out, r);
                }
            }
        } else if sk.kind == SYM_CTOR_FN {
            let built = evalConstructValue(st, units, env, id, sk.a, sk.b, arg_head, true, false, Range { 0, 0 });
            let _ = listUnionHead(st, out, built);
        } else if sk.kind == SYM_PRIM_FN {
            let pm .= units[sk.a - 1];
            let prim = pm.primitives[sk.b];
            if prim.kind == blot_check_core::PrimitiveKind.array {
                if prim.array_op == blot_backend_collection_ops::Op.identity {
                    let _ = listUnionHead(st, out, arg_head);
                } else if prim.array_op == blot_backend_collection_ops::Op.flatten {
                    let f = symFresh(st, env.unit, id, 0);
                    let e1 = stepElemHead(st, env.ctx_id, arg_head);
                    let e2 = stepElemHead(st, env.ctx_id, e1);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, e2) { env.changed = true; }
                    let _ = listAdd(st, out, f);
                }
            }
        } else {
            recordUnresolved(st, env, env.unit, span, blot_check_diagnostic_code::Code.purity_limit, "cannot statically resolve indirect callable in read-only region");
        }
        cc = cn;
    }
    return out;
}

// Unified `Tag.update` evaluator (pure field functional rebind + indexed in-place store, §2.5) — zero resizable locals!
recursive fn evalUpdate(st: Analyzer&, units: const Module[:], env: EvalEnv&, id: u32, depth: i64) -> u32 {
    let m .= units[env.unit - 1];
    let info = m.updateInfo(id);
    let selectors = m.updateSelectors(id);
    let path_projs = m.updatePath(id);
    let smark = st.step_stack.len;
    if selectors.len != 0 {
        for s in selectors {
            if s.kind == blot_check_core::UpdateKind.index {
                st.step_stack.push(NormUpdateStep { is_index: true, index_node: s.index });
            } else {
                let pr = m.projection(s.projection);
                let sp = m.fieldSpelling(pr.field);
                var lbl: u32 = LBL_ANY;
                if sp.present { lbl = internFieldLabel(st, sp.value); }
                st.step_stack.push(NormUpdateStep { is_index: false, field_lbl: lbl });
            }
        }
    } else {
        for p_idx in path_projs {
            let pr = m.projection(p_idx);
            let sp = m.fieldSpelling(pr.field);
            var lbl: u32 = LBL_ANY;
            if sp.present { lbl = internFieldLabel(st, sp.value); }
            st.step_stack.push(NormUpdateStep { is_index: false, field_lbl: lbl });
        }
    }
    let step_len = st.step_stack.len - smark;
    // Visit root AND every index expression.
    let root_head = evalNode(st, units, env, info.root, depth + 1);
    for k in 0..step_len {
        let s = st.step_stack[smark + k];
        if s.is_index && s.index_node != 0 {
            let _ = evalNode(st, units, env, s.index_node, depth + 1);
        }
    }
    // Walk steps[0..step_len] one step at a time using `st.head_stack`.
    let cmark = st.head_stack.len;
    st.head_stack.push(root_head);
    var last_idx: i64 = -1;
    for k in 0..step_len {
        let s = st.step_stack[smark + k];
        let prev_h = st.head_stack[cmark + k];
        if s.is_index {
            last_idx = k;
            st.head_stack.push(stepElemHead(st, env.ctx_id, prev_h));
        } else {
            st.head_stack.push(stepFieldHead(st, env.ctx_id, prev_h, s.field_lbl));
        }
    }
    // Seed self_binding BEFORE visiting RHS on BOTH store==false and store==true.
    if info.self_binding != 0 {
        bindLocal(st, env, info.self_binding, st.head_stack[cmark + step_len]);
    }
    let rhs_head = evalNode(st, units, env, info.value, depth + 1);

    var result_head: u32 = 0;
    if last_idx < 0 && step_len > 0 {
        // Pure field functional rebind.
        let omark = st.head_stack.len;
        for k in 0..step_len {
            st.head_stack.push(symFresh(st, env.unit, id, 10 + (k as u32)));
        }
        for k in 0..step_len {
            let in_k = st.head_stack[cmark + k];
            let out_k = st.head_stack[omark + k];
            let f_next = st.step_stack[smark + k].field_lbl;
            var next_head: u32 = rhs_head;
            if k + 1 < step_len { next_head = listSingle(st, st.head_stack[omark + k + 1]); }
            let emark = st.edge_stack.len;
            var sc = in_k;
            while sc != 0 {
                let s = st.u32_nodes[sc].val;
                let skey = ctxKey(env.ctx_id, s);
                let bopt .= st.ctx_src_base_edges.get(skey);
                if bopt {
                    var ec: u32 = bopt;
                    while ec != 0 {
                        let en = st.edge_nodes[ec];
                        if en.edge.lbl != LBL_CTOR_PAYLOAD { st.edge_stack.push(en.edge); }
                        ec = en.next_src;
                    }
                }
                let wopt .= st.ctx_src_written_edges.get(skey);
                if wopt {
                    var ec: u32 = wopt;
                    while ec != 0 {
                        let en = st.edge_nodes[ec];
                        if en.edge.lbl != LBL_CTOR_PAYLOAD { st.edge_stack.push(en.edge); }
                        ec = en.next_src;
                    }
                }
                sc = st.u32_nodes[sc].next;
            }
            for ei in emark..st.edge_stack.len {
                let e = st.edge_stack[ei];
                if addWrittenEdge(st, env.ctx_id, out_k, e.lbl, e.dst) { env.changed = true; }
            }
            st.edge_stack.resize(emark);
            if addWrittenEdgesSingleSrc(st, env.ctx_id, out_k, f_next, next_head) { env.changed = true; }
            let payload_in = stepCtorHead(st, env.ctx_id, in_k);
            if payload_in != 0 {
                let out_pay = symFresh(st, env.unit, id, 500 + (k as u32));
                let pmark = st.edge_stack.len;
                var psc = payload_in;
                while psc != 0 {
                    let s = st.u32_nodes[psc].val;
                    let skey = ctxKey(env.ctx_id, s);
                    let bopt .= st.ctx_src_base_edges.get(skey);
                    if bopt {
                        var pec: u32 = bopt;
                        while pec != 0 {
                            let en = st.edge_nodes[pec];
                            st.edge_stack.push(en.edge);
                            pec = en.next_src;
                        }
                    }
                    let wopt .= st.ctx_src_written_edges.get(skey);
                    if wopt {
                        var pec: u32 = wopt;
                        while pec != 0 {
                            let en = st.edge_nodes[pec];
                            st.edge_stack.push(en.edge);
                            pec = en.next_src;
                        }
                    }
                    psc = st.u32_nodes[psc].next;
                }
                for ei in pmark..st.edge_stack.len {
                    let e = st.edge_stack[ei];
                    if addWrittenEdge(st, env.ctx_id, out_pay, e.lbl, e.dst) { env.changed = true; }
                }
                st.edge_stack.resize(pmark);
                if addWrittenEdge(st, env.ctx_id, out_k, LBL_CTOR_PAYLOAD, out_pay) { env.changed = true; }
                if addWrittenEdgesSingleSrc(st, env.ctx_id, out_pay, f_next, next_head) { env.changed = true; }
            }
        }
        result_head = listSingle(st, st.head_stack[omark]);
        st.head_stack.resize(omark);
    } else if last_idx >= 0 {
        let target = st.head_stack[cmark + last_idx];
        if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, target) { env.changed = true; }
        if last_idx == step_len - 1 {
            if addWrittenEdgesHeads(st, env.ctx_id, target, LBL_ELEM, rhs_head) { env.changed = true; }
        } else {
            let elem_fresh = symFresh(st, env.unit, id, 100);
            if addWrittenEdgesSingleDst(st, env.ctx_id, target, LBL_ELEM, elem_fresh) { env.changed = true; }
            if addWrittenEdge(st, env.ctx_id, elem_fresh, LBL_CTOR_PAYLOAD, elem_fresh) { env.changed = true; }
            var cur = stepElemHead(st, env.ctx_id, target);
            let trailing = step_len - (last_idx + 1);
            for ti in 0..(trailing - 1) {
                let flbl = st.step_stack[smark + last_idx + 1 + ti].field_lbl;
                var holders: u32 = 0;
                let _ = listUnionHead(st, holders, cur);
                let _ = listUnionHead(st, holders, stepCtorHead(st, env.ctx_id, cur));
                let step_fresh = symFresh(st, env.unit, id, 101 + (ti as u32));
                if addWrittenEdgesSingleDst(st, env.ctx_id, holders, flbl, step_fresh) { env.changed = true; }
                if addWrittenEdge(st, env.ctx_id, step_fresh, LBL_CTOR_PAYLOAD, step_fresh) { env.changed = true; }
                cur = stepFieldHead(st, env.ctx_id, cur, flbl);
            }
            let final_flbl = st.step_stack[smark + step_len - 1].field_lbl;
            var final_holders: u32 = 0;
            let _ = listUnionHead(st, final_holders, cur);
            let _ = listUnionHead(st, final_holders, stepCtorHead(st, env.ctx_id, cur));
            if addWrittenEdgesHeads(st, env.ctx_id, final_holders, final_flbl, rhs_head) { env.changed = true; }
        }
        result_head = root_head;
    } else {
        var fb = root_head;
        if step_len > 0 { fb = st.head_stack[cmark + step_len]; }
        if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, fb) { env.changed = true; }
        if addWrittenEdgesHeads(st, env.ctx_id, fb, LBL_ANY, rhs_head) { env.changed = true; }
    }
    st.head_stack.resize(cmark);
    st.step_stack.resize(smark);
    return result_head;
}

recursive fn evalNode(st: Analyzer&, units: const Module[:], env: EvalEnv&, id: u32, depth: i64) -> u32 {
    if id == 0 || depth > 256 { return 0; }
    let m .= units[env.unit - 1];
    if (id as i64) >= m.nodes.len { return 0; }
    let res = evalNodeRaw(st, units, env, id, depth);
    if res != 0 && isPureScalarCached(st, units, env.unit, m.node(id).ty) { return 0; }
    return res;
}

recursive fn evalNodeRaw(st: Analyzer&, units: const Module[:], env: EvalEnv&, id: u32, depth: i64) -> u32 {
    let m .= units[env.unit - 1];
    let n = m.node(id);
    let cur_hrange = Range { start: env.handlers_base, len: st.handler_stack.len - env.handlers_base };
    match n.tag {
        constant, panic, type_constructor, invalid => { return 0; },
        effect_reflection => {
            if n.a == 2 || n.a == 3 || n.a == 4 { let _ = evalNode(st, units, env, n.b, depth + 1); }
            if n.c != 0 { let _ = evalNode(st, units, env, n.c, depth + 1); }
            return 0;
        },
        scalar, logical, type_same => {
            let _ = evalNode(st, units, env, n.a, depth + 1);
            let _ = evalNode(st, units, env, n.b, depth + 1);
            return 0;
        },
        staging => {
            let _ = evalNode(st, units, env, n.a, depth + 1);
            let _ = evalNode(st, units, env, n.b, depth + 1);
            return 0;
        },
        reference => {
            let r = m.reference(id);
            let is_local = (r.unit == 0 || r.unit == env.unit) &&
                (r.binding as i64) < m.bindings.len &&
                (m.binding(r.binding).kind == blot_reuse_principal_interface::Kind.local ||
                 m.binding(r.binding).kind == blot_reuse_principal_interface::Kind.parameter);
            if is_local {
                let cell_opt .= env.active_with_cells.get(r.binding);
                if cell_opt {
                    let csym: u32 = cell_opt;
                    return stepAnyHead(st, env.ctx_id, listSingle(st, csym));
                }
                let bhead = getBindingHead(st, env.ctx_id, r.binding);
                if st.ctx_cell_bindings.contains(ctxKey(env.ctx_id, r.binding)) {
                    return stepAnyHead(st, env.ctx_id, bhead);
                }
                return bhead;
            }
            let target = blot_check_wire_schema::resolveBindingTarget(units, env.unit, r);
            if target.unit == 0 || target.binding == 0 { return 0; }
            let tm .= units[target.unit - 1];
            let body .= tm.body(target.binding);
            if !body { return 0; }
            let target_fn, found_fn = lookupBodyFn(st, units, target);
            if !found_fn { return 0; }
            if body.is_function {
                return listSingle(st, symFnVal(st, target_fn, symEmptyEnv(st), 0));
            }
            if isPoolType(tm, tm.binding(target.binding).ty) {
                let gsym = symGlobal(st, target.unit, target.binding);
                registerPreExistingRoot(st, env.ctx_id, gsym, true);
                if listAdd(st, st.ctxs[env.ctx_id].reads_globals_head, gsym) { env.changed = true; }
                return listSingle(st, gsym);
            }
            let rn = tm.node(body.root);
            if rn.tag == blot_check_core::Tag.constant { return 0; }
            if rn.tag == blot_check_core::Tag.construct && rn.b == 0 { return 0; }
            if rn.tag == blot_check_core::Tag.flat_op && (rn.c == blot_check_core::flat_op_kernel_handle || rn.c == blot_check_core::flat_op_process_handle) { return 0; }
            let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, 0);
            return invokeSummary(st, env.ctx_id, target_fn, cs_id, Range { 0, 0 }, Range { 0, 0 }, cur_hrange, env.unit, m.span(id), env.changed);
        },
        constructor_function => { return listSingle(st, symCtorFn(st, env.unit, n.a)); },
        primitive_function => { return listSingle(st, symPrimFn(st, env.unit, n.a)); },
        operation_value => {
            let ov = m.operationValue(id);
            if ov.capability != 0 { let _ = evalNode(st, units, env, ov.capability, depth + 1); }
            let op_key = internOpKey(st, ov);
            return listSingle(st, symOpVal(st, op_key));
        },
        closure => {
            let key = ((env.unit as u64) << 32) | (id as u64);
            let fn_opt .= st.closure_fn_map.get(key);
            if !fn_opt { return 0; }
            let target_fn: u32 = fn_opt;
            let env_sym = symFresh(st, env.unit, id, 0);
            let caps = m.closureCaptures(id);
            for ci in 0..caps.len {
                let cb = caps[ci];
                let cell_opt .= env.active_with_cells.get(cb);
                if cell_opt {
                    let csym: u32 = cell_opt;
                    if addWrittenEdge(st, env.ctx_id, env_sym, LBL_CAPTURE_BASE + (ci as u32), csym) { env.changed = true; }
                } else {
                    let chead = getBindingHead(st, env.ctx_id, cb);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, env_sym, LBL_CAPTURE_BASE + (ci as u32), chead) { env.changed = true; }
                }
            }
            return listSingle(st, symFnVal(st, target_fn, env_sym, 0));
        },
        call => {
            let ci = m.call(id);
            let hmark = st.head_stack.len;
            for arg in ci.arguments {
                st.head_stack.push(evalNode(st, units, env, arg, depth + 1));
            }
            let ar = Range { start: hmark, len: st.head_stack.len - hmark };
            let target = blot_check_wire_schema::resolveBindingTarget(units, env.unit, ci.target);
            if target.unit == 0 || target.binding == 0 {
                st.head_stack.resize(hmark);
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "unresolved call target in purity analysis");
                return 0;
            }
            let target_fn, found_fn = lookupBodyFn(st, units, target);
            if !found_fn {
                st.head_stack.resize(hmark);
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "call target has no body in purity analysis");
                return 0;
            }
            let tdef = st.fn_defs[target_fn];
            var ret: u32 = 0;
            if ar.len < (tdef.param_len as i64) {
                let penv = symFresh(st, env.unit, id, 2000);
                for k in 0..ar.len {
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, penv, LBL_CAPTURE_BASE + (k as u32), st.head_stack[ar.start + k]) { env.changed = true; }
                }
                ret = listSingle(st, symFnVal(st, target_fn, penv, ar.len as u8));
            } else {
                let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, 0);
                ret = invokeSummary(st, env.ctx_id, target_fn, cs_id, ar, Range { 0, 0 }, cur_hrange, env.unit, m.span(id), env.changed);
            }
            st.head_stack.resize(hmark);
            return ret;
        },
        apply => {
            let callee_head = evalNode(st, units, env, n.a, depth + 1);
            let arg_head = evalNode(st, units, env, n.b, depth + 1);
            return evalApplyValues(st, units, env, id, 0, callee_head, arg_head, depth + 1);
        },
        product => {
            let kids = m.children(id);
            if isPureScalarCached(st, units, env.unit, n.ty) {
                for i in 0..kids.len { let _ = evalNode(st, units, env, kids[i], depth + 1); }
                return 0;
            }
            let fresh = symFresh(st, env.unit, id, 0);
            for i in 0..kids.len {
                let kh = evalNode(st, units, env, kids[i], depth + 1);
                if addWrittenEdgesSingleSrc(st, env.ctx_id, fresh, LBL_TUPLE_BASE + (i as u32), kh) { env.changed = true; }
            }
            return listSingle(st, fresh);
        },
        record => {
            let kids = m.children(id);
            if isPureScalarCached(st, units, env.unit, n.ty) {
                for i in 0..kids.len { let _ = evalNode(st, units, env, kids[i], depth + 1); }
                return 0;
            }
            let dests = m.recordDestinations(id);
            let fresh = symFresh(st, env.unit, id, 0);
            var rty_id = n.ty;
            if m.types.node(rty_id).tag == blot_check_types::Tag.usage { rty_id = m.types.node(rty_id).a; }
            let rnode = m.types.node(rty_id);
            for i in 0..kids.len {
                let kh = evalNode(st, units, env, kids[i], depth + 1);
                var lbl: u32 = LBL_ANY;
                if rnode.tag == blot_check_types::Tag.record && (dests[i] as i64) < (rnode.b as i64) {
                    let rf = m.types.recordField(rnode, dests[i] as i64);
                    let sp = m.fieldSpelling(rf.name);
                    if sp.present { lbl = internFieldLabel(st, sp.value); }
                }
                if addWrittenEdgesSingleSrc(st, env.ctx_id, fresh, lbl, kh) { env.changed = true; }
            }
            return listSingle(st, fresh);
        },
        array => {
            let kids = m.children(id);
            let fresh = symFresh(st, env.unit, id, 0);
            for k in kids {
                let kh = evalNode(st, units, env, k, depth + 1);
                if addWrittenEdgesSingleSrc(st, env.ctx_id, fresh, LBL_ELEM, kh) { env.changed = true; }
            }
            return listSingle(st, fresh);
        },
        construct => {
            let pure_scalar = isPureScalarCached(st, units, env.unit, n.ty);
            if n.b == 0 {
                if pure_scalar { return 0; }
                return evalConstructValue(st, units, env, id, env.unit, n.a, 0, n.c != 0, false, Range { 0, 0 });
            }
            let bn = m.node(n.b);
            if n.c != 0 && bn.tag == blot_check_core::Tag.product {
                let kids = m.children(n.b);
                if pure_scalar {
                    for i in 0..kids.len { let _ = evalNode(st, units, env, kids[i], depth + 1); }
                    return 0;
                }
                let hmark = st.head_stack.len;
                let p_fresh = symFresh(st, env.unit, n.b, 0);
                for i in 0..kids.len {
                    let kp = evalNode(st, units, env, kids[i], depth + 1);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, p_fresh, LBL_TUPLE_BASE + (i as u32), kp) { env.changed = true; }
                    st.head_stack.push(kp);
                }
                let pr = Range { start: hmark, len: st.head_stack.len - hmark };
                let ret = evalConstructValue(st, units, env, id, env.unit, n.a, listSingle(st, p_fresh), true, true, pr);
                st.head_stack.resize(hmark);
                return ret;
            }
            let payload_head = evalNode(st, units, env, n.b, depth + 1);
            if pure_scalar { return 0; }
            return evalConstructValue(st, units, env, id, env.unit, n.a, payload_head, n.c != 0, false, Range { 0, 0 });
        },
        project => {
            let recv_head = evalNode(st, units, env, n.a, depth + 1);
            let pr = m.projection(n.b);
            let variants = m.projectionVariants(n.b);
            if pr.field == 0 && variants.len == 1 {
                return stepTupleHead(st, env.ctx_id, recv_head, variants[0].field);
            }
            let sp = m.fieldSpelling(pr.field);
            if variants.len != 0 || (sp.present && isDataFieldProjection(units, m, m.typeOf(n.a), sp.value)) {
                let ctor_inner = stepCtorHead(st, env.ctx_id, recv_head);
                var combined: u32 = 0;
                if sp.present {
                    let lbl = internFieldLabel(st, sp.value);
                    let _ = listUnionHead(st, combined, stepFieldHead(st, env.ctx_id, recv_head, lbl));
                    let _ = listUnionHead(st, combined, stepFieldHead(st, env.ctx_id, ctor_inner, lbl));
                    return combined;
                }
                let _ = listUnionHead(st, combined, stepAnyHead(st, env.ctx_id, recv_head));
                let _ = listUnionHead(st, combined, stepAnyHead(st, env.ctx_id, ctor_inner));
                return combined;
            }
            if !sp.present {
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "unresolved method projection in purity analysis");
                return 0;
            }
            let tr = pushAssociatedMethodTargets(st, units, m, m.typeOf(n.a), sp.value, blot_check_types::Operator.none);
            if tr.len == 0 {
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "unresolved method projection target in purity analysis");
                return 0;
            }
            let hmark = st.head_stack.len;
            st.head_stack.push(recv_head);
            let ar = Range { start: hmark, len: 1 };
            var out: u32 = 0;
            for ti in 0..tr.len {
                let tfn, found_fn = lookupBodyFn(st, units, st.target_stack[tr.start + ti]);
                if !found_fn { continue; }
                if (st.fn_defs[tfn].param_len as i64) > 1 {
                    let penv = symFresh(st, env.unit, id, 2100 + (ti as u32));
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, penv, LBL_CAPTURE_BASE, recv_head) { env.changed = true; }
                    let _ = listAdd(st, out, symFnVal(st, tfn, penv, 1));
                } else {
                    let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, ti as u32);
                    let r = invokeSummary(st, env.ctx_id, tfn, cs_id, ar, Range { 0, 0 }, cur_hrange, env.unit, m.span(id), env.changed);
                    let _ = listUnionHead(st, out, r);
                }
            }
            st.head_stack.resize(hmark);
            st.target_stack.resize(tr.start);
            return out;
        },
        result_associated => {
            let recv_head = evalNode(st, units, env, n.a, depth + 1);
            let sp = m.fieldSpelling(n.b);
            if !sp.present {
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "unresolved @type.result in purity analysis");
                return 0;
            }
            let tr = pushAssociatedMethodTargets(st, units, m, m.typeOf(n.a), sp.value, blot_check_types::Operator.none);
            if tr.len == 0 {
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "unresolved @type.result target in purity analysis");
                return 0;
            }
            let hmark = st.head_stack.len;
            st.head_stack.push(recv_head);
            let ar = Range { start: hmark, len: 1 };
            var out: u32 = 0;
            for ti in 0..tr.len {
                let tfn, found_fn = lookupBodyFn(st, units, st.target_stack[tr.start + ti]);
                if !found_fn { continue; }
                let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, ti as u32);
                let r = invokeSummary(st, env.ctx_id, tfn, cs_id, ar, Range { 0, 0 }, cur_hrange, env.unit, m.span(id), env.changed);
                let _ = listUnionHead(st, out, r);
            }
            st.head_stack.resize(hmark);
            st.target_stack.resize(tr.start);
            return out;
        },
        associated => {
            let lhead = evalNode(st, units, env, n.a, depth + 1);
            let rhead = evalNode(st, units, env, n.b, depth + 1);
            var ltid = m.typeOf(n.a);
            for _ in 0..8 {
                if (ltid as i64) >= m.types.nodes.len { break; }
                let ln = m.types.node(ltid);
                if ln.tag == blot_check_types::Tag.usage || ln.tag == blot_check_types::Tag.forall { ltid = ln.a; continue; }
                break;
            }
            var rtid = m.typeOf(n.b);
            for _ in 0..8 {
                if (rtid as i64) >= m.types.nodes.len { break; }
                let rn = m.types.node(rtid);
                if rn.tag == blot_check_types::Tag.usage || rn.tag == blot_check_types::Tag.forall { rtid = rn.a; continue; }
                break;
            }
            let lt = m.types.node(ltid).tag;
            let rt = m.types.node(rtid).tag;
            if (lt == blot_check_types::Tag.unsigned32 || lt == blot_check_types::Tag.floating32 || lt == blot_check_types::Tag.boolean) && lt == rt {
                return 0;
            }
            let sp = m.fieldSpelling(n.c);
            var tr = Range { 0, 0 };
            if sp.present { tr = pushAssociatedMethodTargets(st, units, m, m.typeOf(n.a), sp.value, blot_check_types::Operator.none); }
            else { tr = pushAssociatedMethodTargets(st, units, m, m.typeOf(n.a), "", blot_check_types::Operator.none); }
            if tr.len == 0 { return 0; }
            let hmark = st.head_stack.len;
            st.head_stack.push(lhead);
            st.head_stack.push(rhead);
            let ar = Range { start: hmark, len: 2 };
            var out: u32 = 0;
            for ti in 0..tr.len {
                let tfn, found_fn = lookupBodyFn(st, units, st.target_stack[tr.start + ti]);
                if !found_fn { continue; }
                let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, ti as u32);
                let r = invokeSummary(st, env.ctx_id, tfn, cs_id, ar, Range { 0, 0 }, cur_hrange, env.unit, m.span(id), env.changed);
                let _ = listUnionHead(st, out, r);
            }
            st.head_stack.resize(hmark);
            st.target_stack.resize(tr.start);
            return out;
        },
        contract_method => {
            let kids = m.children(id);
            let hmark = st.head_stack.len;
            for k in kids {
                st.head_stack.push(evalNode(st, units, env, k, depth + 1));
            }
            let ar = Range { start: hmark, len: st.head_stack.len - hmark };
            if (n.a as i64) >= m.member_templates.len { st.head_stack.resize(hmark); return 0; }
            let tmpl = m.member_templates[n.a];
            let sp = m.fieldSpelling(tmpl.name);
            if !sp.present { st.head_stack.resize(hmark); return 0; }
            ensureAssocIndex(st, units);
            let want_lbl = internFieldLabel(st, sp.value);
            let ckey = ((tmpl.contract.unit as u64) << 32) | (tmpl.contract.decl as u64);
            var out: u32 = 0;
            var sub_i: u32 = 0;
            let copt .= st.impl_by_contract.get(ckey);
            if copt {
                var ic: u32 = copt;
                while ic != 0 {
                    let e = st.impl_entries[ic];
                    if e.name_lbl == want_lbl {
                        let tfn, found_fn = lookupBodyFn(st, units, e.target);
                        if found_fn && (st.fn_defs[tfn].param_len as i64) == ar.len {
                            let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, sub_i);
                            sub_i += 1;
                            let r = invokeSummary(st, env.ctx_id, tfn, cs_id, ar, Range { 0, 0 }, cur_hrange, env.unit, m.span(id), env.changed);
                            let _ = listUnionHead(st, out, r);
                        }
                    }
                    ic = e.next_by_contract;
                }
            }
            st.head_stack.resize(hmark);
            return out;
        },
        array_op => {
            let op = m.arrayOperation(id);
            let kids = m.children(id);
            let hmark = st.head_stack.len;
            for k in kids { st.head_stack.push(evalNode(st, units, env, k, depth + 1)); }
            var res: u32 = 0;
            match op {
                length => { res = 0; },
                get => { res = stepElemHead(st, env.ctx_id, st.head_stack[hmark]); },
                identity => { res = st.head_stack[hmark]; },
                set => {
                    let f = symFresh(st, env.unit, id, 0);
                    let old_e = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, old_e) { env.changed = true; }
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, st.head_stack[hmark + 2]) { env.changed = true; }
                    res = listSingle(st, f);
                },
                fill => {
                    let f = symFresh(st, env.unit, id, 0);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, st.head_stack[hmark + 1]) { env.changed = true; }
                    res = listSingle(st, f);
                },
                generate => {
                    let gen_ret = evalApplyValues(st, units, env, id, 10, st.head_stack[hmark + 1], 0, depth + 1);
                    let f = symFresh(st, env.unit, id, 0);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, gen_ret) { env.changed = true; }
                    res = listSingle(st, f);
                },
                append, prepend => {
                    let f = symFresh(st, env.unit, id, 0);
                    let old_e = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, old_e) { env.changed = true; }
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, st.head_stack[hmark + 1]) { env.changed = true; }
                    res = listSingle(st, f);
                },
                concat => {
                    let f = symFresh(st, env.unit, id, 0);
                    let e0 = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                    let e1 = stepElemHead(st, env.ctx_id, st.head_stack[hmark + 1]);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, e0) { env.changed = true; }
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, e1) { env.changed = true; }
                    res = listSingle(st, f);
                },
                slice => {
                    let f = symFresh(st, env.unit, id, 0);
                    let e0 = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, e0) { env.changed = true; }
                    res = listSingle(st, f);
                },
                flatten => {
                    let f = symFresh(st, env.unit, id, 0);
                    let e1 = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                    let e2 = stepElemHead(st, env.ctx_id, e1);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, e2) { env.changed = true; }
                    res = listSingle(st, f);
                },
                simd_load => {
                    let f = symFresh(st, env.unit, id, 0);
                    let e0 = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                    for lane in 0..4 {
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_TUPLE_BASE + (lane as u32), e0) { env.changed = true; }
                    }
                    res = listSingle(st, f);
                },
                simd_store => {
                    let dst_h = st.head_stack[hmark];
                    if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, dst_h) { env.changed = true; }
                    let lane_h = st.head_stack[hmark + 2];
                    for lane in 0..4 {
                        let lval = stepTupleHead(st, env.ctx_id, lane_h, lane as u32);
                        if addWrittenEdgesHeads(st, env.ctx_id, dst_h, LBL_ELEM, lval) { env.changed = true; }
                    }
                    res = dst_h;
                },
            }
            st.head_stack.resize(hmark);
            return res;
        },
        storage => {
            let op, oerr = blot_check_storage_ops::opFromCode(n.c);
            let kids = m.children(id);
            let hmark = st.head_stack.len;
            for k in kids { st.head_stack.push(evalNode(st, units, env, k, depth + 1)); }
            if oerr != blot_error::Error.none {
                st.head_stack.resize(hmark);
                recordUnresolved(st, env, env.unit, m.span(id), blot_check_diagnostic_code::Code.purity_limit, "unknown storage operation in purity analysis");
                return 0;
            }
            var res: u32 = 0;
            match op {
                length => { res = 0; },
                read, load => { res = stepElemHead(st, env.ctx_id, st.head_stack[hmark]); },
                view, at, link => { res = st.head_stack[hmark]; },
                ref => {
                    let f = symFresh(st, env.unit, id, 0);
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, st.head_stack[hmark]) { env.changed = true; }
                    res = listSingle(st, f);
                },
                push => {
                    if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, st.head_stack[hmark]) { env.changed = true; }
                    if addWrittenEdgesHeads(st, env.ctx_id, st.head_stack[hmark], LBL_ELEM, st.head_stack[hmark + 1]) { env.changed = true; }
                    res = 0;
                },
                pop => {
                    if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, st.head_stack[hmark]) { env.changed = true; }
                    res = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                },
                truncate => {
                    if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, st.head_stack[hmark]) { env.changed = true; }
                    res = 0;
                },
                share => {
                    let r = reachHead(st, env.ctx_id, st.head_stack[hmark]);
                    if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, r) { env.changed = true; }
                    res = st.head_stack[hmark];
                },
                copy => {
                    let arg_ty = m.typeOf(kids[0]);
                    if blot_check_storage_types::isArray(m.types, arg_ty) {
                        let f = symFresh(st, env.unit, id, 0);
                        let e0 = stepElemHead(st, env.ctx_id, st.head_stack[hmark]);
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, f, LBL_ELEM, e0) { env.changed = true; }
                        res = listSingle(st, f);
                    } else {
                        res = st.head_stack[hmark];
                    }
                },
            }
            st.head_stack.resize(hmark);
            return res;
        },
        flat_op => {
            if n.c <= blot_check_core::flat_op_kernel_io_hash {
                let _ = evalNode(st, units, env, n.a, depth + 1);
            }
            if n.c == blot_check_core::flat_op_encode || n.c == blot_check_core::flat_op_decode {
                return listSingle(st, symFresh(st, env.unit, id, 0));
            }
            return 0;
        },
        bind => {
            let rhs_head = evalNode(st, units, env, n.b, depth + 1);
            bindLocal(st, env, n.a, rhs_head);
            if n.c >= 2 {
                let outer_b = n.c - 2;
                let cell_opt .= env.active_with_cells.get(outer_b);
                if cell_opt {
                    let csym: u32 = cell_opt;
                    if listAdd(st, st.ctxs[env.ctx_id].mutated_head, csym) { env.changed = true; }
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, csym, LBL_ANY, rhs_head) { env.changed = true; }
                } else {
                    st.ctx_cell_bindings.insert(ctxKey(env.ctx_id, outer_b), true);
                    let cell_targets = getBindingHead(st, env.ctx_id, outer_b);
                    if listUnionHead(st, st.ctxs[env.ctx_id].mutated_head, cell_targets) { env.changed = true; }
                    if addWrittenEdgesHeads(st, env.ctx_id, cell_targets, LBL_ANY, rhs_head) { env.changed = true; }
                }
            }
            return 0;
        },
        pattern_bind => {
            let val_head = evalNode(st, units, env, n.b, depth + 1);
            bindPattern(st, units, env, n.a, val_head, depth + 1);
            if n.c != 0 { let _ = evalNode(st, units, env, n.c, depth + 1); }
            return 0;
        },
        update => { return evalUpdate(st, units, env, id, depth + 1); },
        suite => {
            for ch in m.children(id) { let _ = evalNode(st, units, env, ch, depth + 1); }
            return 0;
        },
        block_ => {
            for ch in m.children(id) { let _ = evalNode(st, units, env, ch, depth + 1); }
            let found .= st.ctx_block_ret.get(ctxKey(env.ctx_id, id));
            if found { let bhead: u32 = found; return bhead; }
            return 0;
        },
        return_ => {
            let val_head = evalNode(st, units, env, n.a, depth + 1);
            if n.b == 0 || n.b == env.root {
                if listUnionHead(st, st.ctxs[env.ctx_id].ret_pts_head, val_head) { env.changed = true; }
            } else {
                let bk = ctxKey(env.ctx_id, n.b);
                var bhead: u32 = 0;
                let existing .= st.ctx_block_ret.get(bk);
                if existing { let h: u32 = existing; bhead = h; }
                if listUnionHead(st, bhead, val_head) {
                    env.changed = true;
                    st.ctx_block_ret.insert(bk, bhead);
                }
            }
            return 0;
        },
        if_value, if_stmt, comptime_if => {
            let _ = evalNode(st, units, env, n.a, depth + 1);
            let t_h = evalNode(st, units, env, n.b, depth + 1);
            let e_h = evalNode(st, units, env, n.c, depth + 1);
            for merge in m.branchMerges(id) {
                bindLocal(st, env, merge.result, getBindingHead(st, env.ctx_id, merge.then_binding));
                bindLocal(st, env, merge.result, getBindingHead(st, env.ctx_id, merge.else_binding));
            }
            var out: u32 = 0;
            let _ = listUnionHead(st, out, t_h);
            let _ = listUnionHead(st, out, e_h);
            return out;
        },
        match_ => {
            let ins = m.matchInputs(id);
            let hmark = st.head_stack.len;
            for x in ins { st.head_stack.push(evalNode(st, units, env, x, depth + 1)); }
            let in_len = st.head_stack.len - hmark;
            var out: u32 = 0;
            for arm in m.matchArms(id) {
                for row in m.armRows(arm) {
                    let pats = m.rowPatterns(row);
                    for at in 0..pats.len {
                        if at < in_len {
                            bindPattern(st, units, env, pats[at], st.head_stack[hmark + at], depth + 1);
                        }
                    }
                }
                if arm.guard_ != 0 { let _ = evalNode(st, units, env, arm.guard_, depth + 1); }
                let bh = evalNode(st, units, env, arm.body, depth + 1);
                let _ = listUnionHead(st, out, bh);
            }
            st.head_stack.resize(hmark);
            for merge in m.branchMerges(id) {
                bindLocal(st, env, merge.result, getBindingHead(st, env.ctx_id, merge.then_binding));
                bindLocal(st, env, merge.result, getBindingHead(st, env.ctx_id, merge.else_binding));
            }
            return out;
        },
        loop_ => {
            let li = m.loopInfo(id);
            let first_h = evalNode(st, units, env, li.first, depth + 1);
            if li.end != 0 { let _ = evalNode(st, units, env, li.end, depth + 1); }
            if li.kind == blot_check_core::LoopKind.array && li.pattern != 0 {
                let elem_h = stepElemHead(st, env.ctx_id, first_h);
                bindPattern(st, units, env, li.pattern, elem_h, depth + 1);
            }
            let carries = m.loopCarries(id);
            for c in carries {
                bindLocal(st, env, c.iteration, getBindingHead(st, env.ctx_id, c.incoming));
            }
            let _ = evalNode(st, units, env, li.body, depth + 1);
            for c in carries {
                bindLocal(st, env, c.iteration, getBindingHead(st, env.ctx_id, c.backedge));
                bindLocal(st, env, c.outgoing, getBindingHead(st, env.ctx_id, c.iteration));
            }
            return 0;
        },
        break_ => {
            let vals = m.breakValues(id);
            let hmark = st.head_stack.len;
            for v in vals { st.head_stack.push(evalNode(st, units, env, v, depth + 1)); }
            let vlen = st.head_stack.len - hmark;
            if n.a != 0 && (n.a as i64) < m.nodes.len && m.node(n.a).tag == blot_check_core::Tag.loop_ {
                let carries = m.loopCarries(n.a);
                for k in 0..carries.len {
                    if k >= vlen { break; }
                    if n.op == blot_check_core::Op.continue_ {
                        bindLocal(st, env, carries[k].iteration, st.head_stack[hmark + k]);
                    } else {
                        bindLocal(st, env, carries[k].outgoing, st.head_stack[hmark + k]);
                    }
                }
            }
            st.head_stack.resize(hmark);
            return 0;
        },
        with_handle => {
            let kids = m.children(id);
            let wmark = st.with_stack.len;
            var ci: u32 = 0;
            for ch in kids {
                let cn = m.node(ch);
                if cn.tag == blot_check_core::Tag.bind && cn.c == 1 && m.node(cn.b).tag == blot_check_core::Tag.reference {
                    let r = m.reference(cn.b);
                    let outer_b = r.binding;
                    let after_b = cn.a;
                    let cell_sym = symFresh(st, env.unit, id, 1000 + ci);
                    ci += 1;
                    var scell: u32 = 0;
                    var shad = false;
                    let prev_cell .= env.active_with_cells.get(outer_b);
                    if prev_cell {
                        let pc: u32 = prev_cell;
                        let init_h = stepAnyHead(st, env.ctx_id, listSingle(st, pc));
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, cell_sym, LBL_ANY, init_h) { env.changed = true; }
                        scell = pc;
                        shad = true;
                    } else {
                        let ov = getBindingHead(st, env.ctx_id, outer_b);
                        if addWrittenEdgesSingleSrc(st, env.ctx_id, cell_sym, LBL_ANY, ov) { env.changed = true; }
                    }
                    env.active_with_cells.insert(outer_b, cell_sym);
                    st.with_stack.push(WithEntry { outer_b: outer_b, after_b: after_b, cell_sym: cell_sym, saved_cell: scell, saved_had: shad });
                }
            }
            let h_mark = st.handler_stack.len;
            for ch in kids {
                let cn = m.node(ch);
                if cn.tag == blot_check_core::Tag.effect_provider {
                    let op_val = m.operationValue(cn.a);
                    let op_key = internOpKey(st, op_val);
                    let hhead = evalNode(st, units, env, cn.b, depth + 1);
                    var hc = hhead;
                    while hc != 0 {
                        let hv = st.u32_nodes[hc].val;
                        let hn = st.u32_nodes[hc].next;
                        let hsk = st.syms[hv];
                        if hsk.kind == SYM_FN_VAL {
                            var k_caps: u16 = st.fn_defs[hsk.a].capture_len as u16;
                            if hsk.sub > 0 { k_caps = hsk.sub as u16; }
                            st.handler_stack.push(ActiveHandlerFrame {
                                op_key: op_key,
                                kind: HANDLER_CLOSURE,
                                fn_id: hsk.a,
                                applied: hsk.sub,
                                env_sym: hsk.b,
                                cap_count: k_caps,
                            });
                        }
                        hc = hn;
                    }
                }
            }
            let wend = st.with_stack.len;
            for wi in wmark..wend {
                let we = st.with_stack[wi];
                if we.saved_had { env.active_with_cells.insert(we.outer_b, we.saved_cell); }
                else { env.active_with_cells.remove(we.outer_b); }
            }
            let body_h = evalNode(st, units, env, n.a, depth + 1);
            st.handler_stack.resize(h_mark);
            for wi in wmark..wend {
                let we = st.with_stack[wi];
                let final_h = stepAnyHead(st, env.ctx_id, listSingle(st, we.cell_sym));
                bindLocal(st, env, we.after_b, final_h);
                if we.saved_had {
                    if addWrittenEdgesSingleSrc(st, env.ctx_id, we.saved_cell, LBL_ANY, final_h) { env.changed = true; }
                }
            }
            st.with_stack.resize(wmark);
            return body_h;
        },
        handle => {
            let pn = m.node(n.a);
            let h_mark = st.handler_stack.len;
            if pn.tag == blot_check_core::Tag.state_provider {
                let init_h = evalNode(st, units, env, pn.c, depth + 1);
                let cell_sym = symFresh(st, env.unit, id, 1000);
                if addWrittenEdgesSingleSrc(st, env.ctx_id, cell_sym, LBL_ANY, init_h) { env.changed = true; }
                let get_key = internOpKey(st, m.operationValue(pn.a));
                let set_key = internOpKey(st, m.operationValue(pn.b));
                st.handler_stack.push(ActiveHandlerFrame { op_key: get_key, kind: HANDLER_STATE_GET, cell_sym: cell_sym, has_cell: true });
                st.handler_stack.push(ActiveHandlerFrame { op_key: set_key, kind: HANDLER_STATE_SET, cell_sym: cell_sym, has_cell: true });
                let inner_h = evalNode(st, units, env, n.b, depth + 1);
                st.handler_stack.resize(h_mark);
                let res_tup = symFresh(st, env.unit, id, 0);
                let final_state = stepAnyHead(st, env.ctx_id, listSingle(st, cell_sym));
                if addWrittenEdgesSingleSrc(st, env.ctx_id, res_tup, LBL_TUPLE_BASE + 0, final_state) { env.changed = true; }
                if addWrittenEdgesSingleSrc(st, env.ctx_id, res_tup, LBL_TUPLE_BASE + 1, inner_h) { env.changed = true; }
                return listSingle(st, res_tup);
            }
            if pn.tag == blot_check_core::Tag.effect_provider {
                let op_key = internOpKey(st, m.operationValue(pn.a));
                let hhead = evalNode(st, units, env, pn.b, depth + 1);
                var hc = hhead;
                while hc != 0 {
                    let hv = st.u32_nodes[hc].val;
                    let hn = st.u32_nodes[hc].next;
                    let hsk = st.syms[hv];
                    if hsk.kind == SYM_FN_VAL {
                        var k_caps: u16 = st.fn_defs[hsk.a].capture_len as u16;
                        if hsk.sub > 0 { k_caps = hsk.sub as u16; }
                        st.handler_stack.push(ActiveHandlerFrame {
                            op_key: op_key,
                            kind: HANDLER_CLOSURE,
                            fn_id: hsk.a,
                            applied: hsk.sub,
                            env_sym: hsk.b,
                            cap_count: k_caps,
                        });
                    }
                    hc = hn;
                }
                let inner_h = evalNode(st, units, env, n.b, depth + 1);
                st.handler_stack.resize(h_mark);
                return inner_h;
            }
            let _ = evalNode(st, units, env, n.a, depth + 1);
            return evalNode(st, units, env, n.b, depth + 1);
        },
        effect_provider, state_provider => {
            let _ = evalNode(st, units, env, n.b, depth + 1);
            if n.tag == blot_check_core::Tag.state_provider { let _ = evalNode(st, units, env, n.c, depth + 1); }
            return 0;
        },
        fork_ => {
            return evalNode(st, units, env, n.a, depth + 1);
        },
        comptime_for => {
            let _ = evalNode(st, units, env, n.b, depth + 1);
            return 0;
        },
        comptime_meta => {
            if n.c == 0 { return evalNode(st, units, env, n.a, depth + 1); }
            if n.c == 8 || n.c == 9 { return evalNode(st, units, env, n.b, depth + 1); }
            return 0;
        },
        spark => {
            let si = m.sparkInfo(id);
            let src_head = evalNode(st, units, env, si.source, depth + 1);
            if si.end != 0 { let _ = evalNode(st, units, env, si.end, depth + 1); }
            let key = ((env.unit as u64) << 32) | (id as u64);
            let sfn_opt .= st.spark_fn_map.get(key);
            if !sfn_opt { return 0; }
            let sfn_id: u32 = sfn_opt;
            let hmark = st.head_stack.len;
            if !si.is_range { st.head_stack.push(src_head); }
            let ar = Range { start: hmark, len: st.head_stack.len - hmark };
            let cmark = st.head_stack.len;
            for cb in m.sparkCaptures(id) { st.head_stack.push(getBindingHead(st, env.ctx_id, cb)); }
            let cr = Range { start: cmark, len: st.head_stack.len - cmark };
            let empty_hr = Range { start: 0, len: 0 };
            let cs_id = internCallSite(st, st.ctxs[env.ctx_id].fn_id, env.unit, id, 0);
            let elem_ret = invokeSummary(st, env.ctx_id, sfn_id, cs_id, ar, cr, empty_hr, env.unit, m.span(id), env.changed);
            var found_sctx: u32 = 0xffffffff;
            {
                let cspecs = buildCallableSpecsRange(st, env.ctx_id, ar, cr);
                let empty_hs: HandlerSpec[0] = [];
                let sc_id, ok = getOrCreateCtx(st, sfn_id, cspecs[..], empty_hs[..], env.unit, m.span(id));
                if ok { found_sctx = sc_id; }
            }
            st.head_stack.resize(hmark);
            if found_sctx != 0xffffffff {
                if !si.is_range {
                    let p0 = symParam(st, 0);
                    registerPreExistingRoot(st, found_sctx, p0, true);
                }
                var existing_idx: i64 = -1;
                for sci in 0..st.spark_checks.len {
                    if st.spark_checks[sci].enclosing_ctx == env.ctx_id && st.spark_checks[sci].spark_node == id {
                        existing_idx = sci;
                        break;
                    }
                }
                if existing_idx < 0 {
                    var sh: u32 = 0;
                    let _ = listUnionHead(st, sh, src_head);
                    let cstart = st.spark_cap_bindings.len as u32;
                    let cap_bs2 = m.sparkCaptures(id);
                    let clen = cap_bs2.len as u32;
                    for cb in cap_bs2 { st.spark_cap_bindings.push(cb); }
                    st.spark_checks.push(SparkCheck {
                        unit: env.unit,
                        spark_node: id,
                        enclosing_ctx: env.ctx_id,
                        spark_ctx: found_sctx,
                        is_range: si.is_range,
                        src_head: sh,
                        cap_start: cstart,
                        cap_len: clen,
                        span: m.span(id),
                    });
                } else {
                    st.spark_checks[existing_idx].spark_ctx = found_sctx;
                    let _ = listUnionHead(st, st.spark_checks[existing_idx].src_head, src_head);
                }
            }
            let out_arr = symFresh(st, env.unit, id, 0);
            if addWrittenEdgesSingleSrc(st, env.ctx_id, out_arr, LBL_ELEM, elem_ret) { env.changed = true; }
            return listSingle(st, out_arr);
        },
    }
}

fn analyzeCtx(st: Analyzer&, units: const Module[:], ctx_id: u32) {
    let def = st.fn_defs[st.ctxs[ctx_id].fn_id];
    let hbase = st.handler_stack.len;
    var env = EvalEnv { ctx_id: ctx_id, unit: def.unit, root: def.root, handlers_base: hbase };
    if def.kind == FN_SPARK {
        let m .= units[def.unit - 1];
        let si = m.sparkInfo(def.node_id);
        if !si.is_range && si.pattern != 0 {
            let p0 = symParam(st, 0);
            registerPreExistingRoot(st, ctx_id, p0, true);
            let elem_h = stepElemHead(st, ctx_id, listSingle(st, p0));
            bindPattern(st, units, env, si.pattern, elem_h, 0);
        }
    }
    let prev_unresolved = st.ctxs[ctx_id].unresolved_error;
    var iter: i64 = 0;
    loop {
        env.changed = false;
        st.ctxs[ctx_id].unresolved_error = false;
        let ret_h = evalNode(st, units, env, def.root, 0);
        if listUnionHead(st, st.ctxs[ctx_id].ret_pts_head, ret_h) { env.changed = true; }
        iter += 1;
        if !env.changed || iter >= 64 { break; }
    }
    st.handler_stack.resize(hbase);
    st.ctxs[ctx_id].analyzed = true;
    let _ = publishSummary(st, ctx_id, prev_unresolved != st.ctxs[ctx_id].unresolved_error);
}

fn runWorklist(st: Analyzer&, units: const Module[:]) {
    var steps: i64 = 0;
    while st.worklist.len != 0 && steps < 50000 {
        let ctx_id = st.worklist[st.worklist.len - 1];
        st.worklist.resize(st.worklist.len - 1);
        if !st.ctxs[ctx_id].dirty { continue; }
        st.ctxs[ctx_id].dirty = false;
        analyzeCtx(st, units, ctx_id);
        steps += 1;
    }
}

// ---- Entry Drivers & Final Mathematical Law Verification (§2.5) ----

fn hasAnyConcurrencyFeature(units: const Module[:], entry: u32) -> bool {
    if hasUnit(units, entry) {
        let em .= units[entry - 1];
        if em.kernels.len != 0 || em.processes.len != 0 { return true; }
    }
    for m in units {
        if m.sparks.len != 0 { return true; }
    }
    return false;
}

fn isDeeplyImmutable(map: const dictionary<BindingRef, bool>&, gref: BindingRef) -> bool {
    let opt .= map.get(gref);
    if !opt { return false; }
    let v: bool = opt;
    return v;
}

fn analyze(units: const Module[:], entry: u32) -> Result {
    var ignored: u64[>..] = [];
    return analyzeInto(units, entry, ignored);
}

fn analyzeInto(units: const Module[:], entry: u32, out_deeply_immutable: u64[>..]& ) -> Result {
    var res = Result {};
    if !hasUnit(units, entry) { return res; }
    if !hasAnyConcurrencyFeature(units, entry) { return res; }

    var st = Analyzer { entry: entry };
    initAnalyzerSentinels(st);
    let empty_cs: CallableSpec[0] = [];
    let empty_hs: HandlerSpec[0] = [];
    let em .= units[entry - 1];

    // Fast body-header scan (no AST node walk): collect module-level pool
    // globals and any module global whose type contains a mutable GrowArray /
    // ResizeArray. After Memory Model Phases 1–5 (no `=`, no `lent`, unique
    // `:=` and `@simd.store`), non-growable globals cannot be mutated after
    // startup unless they retain a handle/view to a growable global.
    var mutable_globals: BindingRef[>..] = [];
    for u_idx in 0..units.len {
        let m .= units[u_idx];
        let unit = m.unit;
        for bi in 1..m.bodies.len {
            let body = m.bodies[bi];
            if body.is_function || (body.binding as i64) >= m.bindings.len { continue; }
            let ty = m.binding(body.binding).ty;
            let gref = BindingRef { unit: unit, binding: body.binding };
            if isPoolType(m, ty) { st.pool_globals.push(gref); }
            if typeHasMutableArray(units, unit, ty, 0) { mutable_globals.push(gref); }
        }
    }
    let has_mutable_global = mutable_globals.len != 0;

    // 1. Seed ONLY concurrency roots (kernels, processes, spark bodies), plus
    // immutable-typed pool initializers only when a mutable global exists in
    // the program (to detect views/aliases to mutable globals).
    var pool_ctxs: u32[>..] = [];
    var pool_ctx_globals: BindingRef[>..] = [];
    if has_mutable_global {
        for pg in st.pool_globals {
            let pm .= units[pg.unit - 1];
            if typeHasMutableArray(units, pg.unit, pm.binding(pg.binding).ty, 0) { continue; }
            let fid, found_fn = lookupBodyFn(st, units, pg);
            if !found_fn { continue; }
            let cid, ok = getOrCreateCtx(st, fid, empty_cs[..], empty_hs[..], pg.unit, st.fn_defs[fid].span);
            if ok {
                pool_ctxs.push(cid);
                pool_ctx_globals.push(pg);
            }
        }
    }

    var kernel_prep_ctxs: u32[>..] = [];
    var kernel_run_ctxs: u32[>..] = [];
    for ki in 0..em.kernels.len {
        let kd = em.kernels[ki];
        var prep_cid: u32 = 0xffffffff;
        if kd.has_context {
            let pt = blot_check_wire_schema::resolveBindingTarget(units, entry, kd.prepare_target);
            let fid, found_fn = lookupBodyFn(st, units, pt);
            if found_fn {
                let cid, ok = getOrCreateCtx(st, fid, empty_cs[..], empty_hs[..], entry, kd.span);
                if ok { prep_cid = cid; }
            }
        }
        kernel_prep_ctxs.push(prep_cid);
        var run_cid: u32 = 0xffffffff;
        let rt = blot_check_wire_schema::resolveBindingTarget(units, entry, kd.run_target);
        let fid, found_fn = lookupBodyFn(st, units, rt);
        if found_fn {
            let cid, ok = getOrCreateCtx(st, fid, empty_cs[..], empty_hs[..], entry, kd.span);
            if ok { run_cid = cid; }
        }
        kernel_run_ctxs.push(run_cid);
    }

    var proc_init_ctxs: u32[>..] = [];
    var proc_step_ctxs: u32[>..] = [];
    for pi in 0..em.processes.len {
        let pd = em.processes[pi];
        var init_cid: u32 = 0xffffffff;
        let it = blot_check_wire_schema::resolveBindingTarget(units, entry, pd.init_target);
        let fid, found_fn = lookupBodyFn(st, units, it);
        if found_fn {
            let cid, ok = getOrCreateCtx(st, fid, empty_cs[..], empty_hs[..], entry, pd.span);
            if ok { init_cid = cid; }
        }
        proc_init_ctxs.push(init_cid);
        var step_cid: u32 = 0xffffffff;
        let stt = blot_check_wire_schema::resolveBindingTarget(units, entry, pd.step_target);
        let sfid, sfound = lookupBodyFn(st, units, stt);
        if sfound {
            let cid, ok = getOrCreateCtx(st, sfid, empty_cs[..], empty_hs[..], entry, pd.span);
            if ok { step_cid = cid; }
        }
        proc_step_ctxs.push(step_cid);
    }

    for u_idx in 0..units.len {
        let um .= units[u_idx];
        if um.sparks.len == 0 { continue; }
        for bi in 1..um.bodies.len {
            let fid, found_fn = lookupBodyFn(st, units, BindingRef { unit: um.unit, binding: um.bodies[bi].binding });
            if !found_fn { continue; }
            let _, _ = getOrCreateCtx(st, fid, empty_cs[..], empty_hs[..], um.unit, um.bodies[bi].span);
        }
    }

    // 2. Run interprocedural worklist to Tarski least fixed point!
    runWorklist(st, units);
    if st.fatal_issue.failed {
        res.issue = st.fatal_issue;
        return res;
    }

    // 3. Compute start-time pool global-containment & `mutated_after_start` (§2.5).
    var mutated_after_start: dictionary<u32, bool> = dictionary<u32, bool>{};
    for mg in mutable_globals {
        mutated_after_start.insert(symGlobal(st, mg.unit, mg.binding), true);
    }
    for pi in 0..pool_ctxs.len {
        let cid = pool_ctxs[pi];
        let pg = pool_ctx_globals[pi];
        let gsym = symGlobal(st, pg.unit, pg.binding);
        let r_init = reachHead(st, cid, st.ctxs[cid].ret_pts_head);
        var hhead: u32 = 0;
        var rc = r_init;
        while rc != 0 {
            let s = st.u32_nodes[rc].val;
            let rn = st.u32_nodes[rc].next;
            if st.syms[s].kind == SYM_GLOBAL { let _ = listAdd(st, hhead, s); }
            rc = rn;
        }
        st.pool_contains_globals.insert(gsym, hhead);
        var mc = st.ctxs[cid].mutated_head;
        while mc != 0 {
            let m_sym = st.u32_nodes[mc].val;
            let sk = st.syms[m_sym];
            if sk.kind == SYM_GLOBAL { mutated_after_start.insert(m_sym, true); }
            else if sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL { mutated_after_start.insert(sk.a, true); }
            mc = st.u32_nodes[mc].next;
        }
    }

    var all_runtime_ctxs: u32[>..] = [];
    for cid in kernel_prep_ctxs { if cid != 0xffffffff { all_runtime_ctxs.push(cid); } }
    for cid in kernel_run_ctxs { if cid != 0xffffffff { all_runtime_ctxs.push(cid); } }
    for cid in proc_init_ctxs { if cid != 0xffffffff { all_runtime_ctxs.push(cid); } }
    for cid in proc_step_ctxs { if cid != 0xffffffff { all_runtime_ctxs.push(cid); } }

    for cid in all_runtime_ctxs {
        var mc = st.ctxs[cid].mutated_head;
        while mc != 0 {
            let m_sym = st.u32_nodes[mc].val;
            let sk = st.syms[m_sym];
            if sk.kind == SYM_GLOBAL { mutated_after_start.insert(m_sym, true); }
            else if sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL { mutated_after_start.insert(sk.a, true); }
            mc = st.u32_nodes[mc].next;
        }
    }

    // 4. Synthetic multi-turn `entry process` driver analysis (§2.5)!
    var proc_driver_mutates_global: bool[>..] = [];
    for pi in 0..em.processes.len {
        let init_cid = proc_init_ctxs[pi];
        let step_cid = proc_step_ctxs[pi];
        var mutates_g = false;
        if init_cid != 0xffffffff && step_cid != 0xffffffff {
            let drv_ctx = st.ctxs.len as u32;
            st.ctxs.push(FnCtx { fn_id: 0, dirty: false });
            let wire_cfg = symFresh(st, entry, pi as u32, 9001);
            let wire_cmd = symFresh(st, entry, pi as u32, 9002);
            let init_cs = internCallSite(st, 0, entry, pi as u32, 9003);
            let step_cs = internCallSite(st, 0, entry, pi as u32, 9004);
            var st_head: u32 = 0;
            var drv_changed = false;
            let imark = st.head_stack.len;
            st.head_stack.push(listSingle(st, wire_cfg));
            let r0 = invokeSummary(st, drv_ctx, st.ctxs[init_cid].fn_id, init_cs, Range { start: imark, len: 1 }, Range { 0, 0 }, Range { 0, 0 }, entry, em.processes[pi].span, drv_changed);
            st.head_stack.resize(imark);
            let _ = listUnionHead(st, st_head, r0);
            for _ in 0..32 {
                drv_changed = false;
                let smark = st.head_stack.len;
                st.head_stack.push(st_head);
                st.head_stack.push(listSingle(st, wire_cmd));
                let pair_h = invokeSummary(st, drv_ctx, st.ctxs[step_cid].fn_id, step_cs, Range { start: smark, len: 2 }, Range { 0, 0 }, Range { 0, 0 }, entry, em.processes[pi].span, drv_changed);
                st.head_stack.resize(smark);
                let next_st = stepTupleHead(st, drv_ctx, pair_h, 0);
                if listUnionHead(st, st_head, next_st) { drv_changed = true; }
                if !drv_changed { break; }
            }
            var mc = st.ctxs[drv_ctx].mutated_head;
            while mc != 0 {
                let m_sym = st.u32_nodes[mc].val;
                let sk = st.syms[m_sym];
                if sk.kind == SYM_GLOBAL {
                    mutated_after_start.insert(m_sym, true);
                    mutates_g = true;
                } else if sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL {
                    mutated_after_start.insert(sk.a, true);
                    mutates_g = true;
                }
                mc = st.u32_nodes[mc].next;
            }
        }
        proc_driver_mutates_global.push(mutates_g);
    }

    // 5. Compute `deeply_immutable[g]` for every global pool (§2.5).
    var deeply_immutable: dictionary<BindingRef, bool> = dictionary<BindingRef, bool>{};
    for pg in st.pool_globals {
        let pm .= units[pg.unit - 1];
        let gsym = symGlobal(st, pg.unit, pg.binding);
        var imm = !typeHasMutableArray(units, pg.unit, pm.binding(pg.binding).ty, 0);
        if imm {
            var q: u32[>..] = [gsym];
            var seen: dictionary<u32, bool> = dictionary<u32, bool>{};
            seen.insert(gsym, true);
            var qi: i64 = 0;
            while qi < q.len {
                let cur = q[qi];
                qi += 1;
                if mutated_after_start.contains(cur) { imm = false; break; }
                let next_opt .= st.pool_contains_globals.get(cur);
                if next_opt {
                    let nhead: u32 = next_opt;
                    var nc = nhead;
                    while nc != 0 {
                        let nx = st.u32_nodes[nc].val;
                        if !seen.contains(nx) { seen.insert(nx, true); q.push(nx); }
                        nc = st.u32_nodes[nc].next;
                    }
                }
            }
        }
        deeply_immutable.insert(pg, imm);
    }
    // Emit sorted deeply-immutable pool keys and deterministic whole-program digest for LayoutReceipt (§4.1).
    {
        var sorted_pgs: BindingRef[>..] = [];
        for pg in st.pool_globals { sorted_pgs.push(pg); }
        for i in 1..sorted_pgs.len {
            let moved = sorted_pgs[i];
            var j = i;
            while j > 0 && (moved.unit < sorted_pgs[j - 1].unit || (moved.unit == sorted_pgs[j - 1].unit && moved.binding < sorted_pgs[j - 1].binding)) {
                sorted_pgs[j] = sorted_pgs[j - 1];
                j -= 1;
            }
            sorted_pgs[j] = moved;
        }
        var dig: u64 = 0xcbf29ce484222325;
        let prime: u64 = 0x100000001b3;
        for pg in sorted_pgs {
            let imm = isDeeplyImmutable(deeply_immutable, pg);
            dig = (dig ^ (pg.unit as u64)) * prime;
            dig = (dig ^ (pg.binding as u64)) * prime;
            var ib: u64 = 0;
            if imm {
                ib = 1;
                out_deeply_immutable.push(((pg.unit as u64) << 32) | (pg.binding as u64));
            }
            dig = (dig ^ ib) * prime;
        }
        res.deeply_immutable_digest = dig;
    }

    // 6. Enforce Mathematical Law 1: `spark` read-only footprint (`spark_mutates_capture`).
    for sci in 0..st.spark_checks.len {
        let sc = st.spark_checks[sci];
        let sctx = sc.spark_ctx;
        if st.ctxs[sctx].unresolved_error {
            res.issue = Issue {
                failed: true,
                unit: st.ctxs[sctx].error_unit,
                span: st.ctxs[sctx].error_span,
                code: blot_check_diagnostic_code::Code.spark_mutates_capture,
                message: st.ctxs[sctx].error_msg,
            };
            return res;
        }
        var prot_seeds: u32 = 0;
        if !sc.is_range { let _ = listUnionHead(st, prot_seeds, sc.src_head); }
        for ci in 0..(sc.cap_len as i64) {
            let cb = st.spark_cap_bindings[(sc.cap_start as i64) + ci];
            let _ = listUnionHead(st, prot_seeds, getBindingHead(st, sc.enclosing_ctx, cb));
        }
        let protected_h = reachHead(st, sc.enclosing_ctx, prot_seeds);
        let cs_id = internCallSite(st, st.ctxs[sc.enclosing_ctx].fn_id, sc.unit, sc.spark_node, 0);
        let hmark = st.head_stack.len;
        if !sc.is_range { st.head_stack.push(sc.src_head); }
        let ar = Range { start: hmark, len: st.head_stack.len - hmark };
        let cmark = st.head_stack.len;
        for ci in 0..(sc.cap_len as i64) {
            let cb = st.spark_cap_bindings[(sc.cap_start as i64) + ci];
            st.head_stack.push(getBindingHead(st, sc.enclosing_ctx, cb));
        }
        let cr = Range { start: cmark, len: st.head_stack.len - cmark };
        var mc = st.ctxs[sctx].sum_mut_head;
        while mc != 0 {
            let m_sym = st.u32_nodes[mc].val;
            let mn = st.u32_nodes[mc].next;
            let mapped_h = applySigmaStar(st, sc.enclosing_ctx, cs_id, ar, cr, Range { 0, 0 }, m_sym);
            var tc = mapped_h;
            while tc != 0 {
                let target = st.u32_nodes[tc].val;
                let tsk = st.syms[target];
                let hits_global = tsk.kind == SYM_GLOBAL || (tsk.kind == SYM_CHILD && st.syms[tsk.a].kind == SYM_GLOBAL);
                if hits_global || listHas(st, protected_h, target) {
                    st.head_stack.resize(hmark);
                    res.issue = Issue {
                        failed: true,
                        unit: sc.unit,
                        span: sc.span,
                        code: blot_check_diagnostic_code::Code.spark_mutates_capture,
                        message: "spark body mutates storage reachable from an outer capture, generator source, or global",
                    };
                    return res;
                }
                tc = st.u32_nodes[tc].next;
            }
            mc = mn;
        }
        st.head_stack.resize(hmark);
    }

    // 7. Enforce Mathematical Law 2: `entry kernel` read-only footprint (`kernel_mutates_context`).
    for ki in 0..em.kernels.len {
        let kd = em.kernels[ki];
        let prep_cid = kernel_prep_ctxs[ki];
        if prep_cid != 0xffffffff {
            if st.ctxs[prep_cid].unresolved_error {
                res.issue = Issue { failed: true, unit: entry, span: kd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: st.ctxs[prep_cid].error_msg };
                return res;
            }
            let prot_h = reachHead(st, prep_cid, listSingle(st, symParam(st, 0)));
            var mc = st.ctxs[prep_cid].mutated_head;
            while mc != 0 {
                let m_sym = st.u32_nodes[mc].val;
                let sk = st.syms[m_sym];
                let is_g = sk.kind == SYM_GLOBAL || (sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL);
                if is_g || listHas(st, prot_h, m_sym) {
                    res.issue = Issue { failed: true, unit: entry, span: kd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: "entry kernel prepare mutates its WireCtx or a module global" };
                    return res;
                }
                mc = st.u32_nodes[mc].next;
            }
            var gc = st.ctxs[prep_cid].reads_globals_head;
            while gc != 0 {
                let gsk = st.syms[st.u32_nodes[gc].val];
                let gref = BindingRef { unit: gsk.a, binding: gsk.b };
                if !isDeeplyImmutable(deeply_immutable, gref) {
                    res.issue = Issue { failed: true, unit: entry, span: kd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: "entry kernel prepare reads a module global that is not deeply immutable" };
                    return res;
                }
                gc = st.u32_nodes[gc].next;
            }
        }
        let run_cid = kernel_run_ctxs[ki];
        if run_cid != 0xffffffff {
            if st.ctxs[run_cid].unresolved_error {
                res.issue = Issue { failed: true, unit: entry, span: kd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: st.ctxs[run_cid].error_msg };
                return res;
            }
            var rseeds: u32 = listSingle(st, symParam(st, 0));
            if kd.has_context { let _ = listAdd(st, rseeds, symParam(st, 1)); }
            let prot_h = reachHead(st, run_cid, rseeds);
            var mc = st.ctxs[run_cid].mutated_head;
            while mc != 0 {
                let m_sym = st.u32_nodes[mc].val;
                let sk = st.syms[m_sym];
                let is_g = sk.kind == SYM_GLOBAL || (sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL);
                if is_g || listHas(st, prot_h, m_sym) {
                    res.issue = Issue { failed: true, unit: entry, span: kd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: "entry kernel run mutates its PreparedCtx, Item, or a module global" };
                    return res;
                }
                mc = st.u32_nodes[mc].next;
            }
            var gc = st.ctxs[run_cid].reads_globals_head;
            while gc != 0 {
                let gsk = st.syms[st.u32_nodes[gc].val];
                let gref = BindingRef { unit: gsk.a, binding: gsk.b };
                if !isDeeplyImmutable(deeply_immutable, gref) {
                    res.issue = Issue { failed: true, unit: entry, span: kd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: "entry kernel run reads a module global that is not deeply immutable" };
                    return res;
                }
                gc = st.u32_nodes[gc].next;
            }
        }
    }

    // 8. Enforce Mathematical Law 3: `entry process` read-only wire input + deeply-immutable globals + cross-turn driver (`process_mutates_global`).
    for pi in 0..em.processes.len {
        let pd = em.processes[pi];
        if proc_driver_mutates_global[pi] {
            res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: "entry process mutates a module global through its state across turns" };
            return res;
        }
        let init_cid = proc_init_ctxs[pi];
        if init_cid != 0xffffffff {
            if st.ctxs[init_cid].unresolved_error {
                res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: st.ctxs[init_cid].error_msg };
                return res;
            }
            let prot_h = reachHead(st, init_cid, listSingle(st, symParam(st, 0)));
            var mc = st.ctxs[init_cid].mutated_head;
            while mc != 0 {
                let m_sym = st.u32_nodes[mc].val;
                let sk = st.syms[m_sym];
                let is_g = sk.kind == SYM_GLOBAL || (sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL);
                if is_g {
                    res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: "entry process init mutates a module global" };
                    return res;
                }
                if listHas(st, prot_h, m_sym) {
                    res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: "entry process init mutates its Config input" };
                    return res;
                }
                mc = st.u32_nodes[mc].next;
            }
            var gc = st.ctxs[init_cid].reads_globals_head;
            while gc != 0 {
                let gsk = st.syms[st.u32_nodes[gc].val];
                let gref = BindingRef { unit: gsk.a, binding: gsk.b };
                if !isDeeplyImmutable(deeply_immutable, gref) {
                    res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: "entry process init reads a module global that is not deeply immutable" };
                    return res;
                }
                gc = st.u32_nodes[gc].next;
            }
        }
        let step_cid = proc_step_ctxs[pi];
        if step_cid != 0xffffffff {
            if st.ctxs[step_cid].unresolved_error {
                res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: st.ctxs[step_cid].error_msg };
                return res;
            }
            let prot_cmd_h = reachHead(st, step_cid, listSingle(st, symParam(st, 1)));
            var mc = st.ctxs[step_cid].mutated_head;
            while mc != 0 {
                let m_sym = st.u32_nodes[mc].val;
                let sk = st.syms[m_sym];
                let is_g = sk.kind == SYM_GLOBAL || (sk.kind == SYM_CHILD && st.syms[sk.a].kind == SYM_GLOBAL);
                if is_g {
                    res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: "entry process step mutates a module global" };
                    return res;
                }
                if listHas(st, prot_cmd_h, m_sym) {
                    res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.kernel_mutates_context, message: "entry process step mutates its Cmd input" };
                    return res;
                }
                mc = st.u32_nodes[mc].next;
            }
            var gc = st.ctxs[step_cid].reads_globals_head;
            while gc != 0 {
                let gsk = st.syms[st.u32_nodes[gc].val];
                let gref = BindingRef { unit: gsk.a, binding: gsk.b };
                if !isDeeplyImmutable(deeply_immutable, gref) {
                    res.issue = Issue { failed: true, unit: entry, span: pd.span, code: blot_check_diagnostic_code::Code.process_mutates_global, message: "entry process step reads a module global that is not deeply immutable" };
                    return res;
                }
                gc = st.u32_nodes[gc].next;
            }
        }
    }

    return res;
}
