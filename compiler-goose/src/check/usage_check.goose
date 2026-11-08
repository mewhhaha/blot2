// Affine moves follow resolved binding versions and exact lexical owners.
namespace blot_check_usage_check;
import check.capability_flow;
import reuse.principal_interface;

import check.check_packet_owner;
import check.cleanup_contracts;
import check.core;
import check.task_types;
import check.types;
import parse.ast;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;
import support.structural_adapters;

import support.structural;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type Tag = blot_check_types::Tag;
type AstId = blot_parse_ast::Id;
struct State { binding: u32, first: AstId = 0, loan: AstId = 0 }
enum Outcome { live, exit }
type StateBuffer=blot_support_pooled_buffer::Buffer<State>;
type IdBuffer=blot_support_pooled_buffer::Buffer<u32>;
reusable[] var state_scratch:State[>..];
reusable[] var capture_scratch:u32[>..];
struct ExitFrame { joined: State[:], seen: bool = false }
struct Work { remaining: i64 = 65536 }
fn charge(self_: Work&, amount: i64) -> Error { if amount > self_.remaining { return blot_error::Error.type_limit; } self_.remaining -= amount; return blot_error::Error.none; }
struct NominalFact { identity: blot_check_types::NominalIdentity, has_usage: bool }
struct Memo { safe: dictionary<Id,bool>&, epoch: blot_support::Option<u64>   = blot_support::none<u64>(), row_epoch: blot_support::Option<u64>   = blot_support::none<u64>(), nominals: NominalFact[>..<]& }
fn initMemo(safe: dictionary<Id,bool>&, nominals: NominalFact[>..<]&) -> Memo { return Memo { safe: safe, nominals: nominals , ..}; }
fn deinit(self_: Memo&) { self_.safe.clear(); self_.nominals.clear(); }
enum Mode { affine, any, borrow }
struct NominalStore<S,N> { store: S, nominals: N, work: Work& }
fn head<S,N>(self_: const NominalStore<S,N>&, id: Id, cursor: u32) -> Id { return self_.store.head(id, cursor); }
fn node<S,N>(self_: const NominalStore<S,N>&, id: Id) -> blot_check_types::Node { return self_.store.node(id); }
fn list<S,N>(self_: const NominalStore<S,N>&, values: blot_check_types::List) -> const Id[:] { return self_.store.list(values); }
fn recordField<S,N>(self_: const NominalStore<S,N>&, value: blot_check_types::Node, index: i64) -> blot_check_types::Field { return self_.store.recordField(value, index); }
fn nominalArguments<S,N>(self_: const NominalStore<S,N>&, value: blot_check_types::Node) -> const Id[:] { return self_.store.nominalArguments(value); }
fn valid<S,N>(self_: const NominalStore<S,N>&, id: Id) -> bool { return id < self_.store.nodes.len; }
fn extraValues(values:const Id[:])->const Id[:] {return values;}
fn extraValues(values:const blot_check_types::Table_extra&)->const Id[:] {return values.items;}
fn shape<S,N>(self_: const NominalStore<S,N>&, value: blot_check_types::Node) -> Error {
    let values = extraValues(self_.store.extra);
    match value.tag {
        usage, array, list, cursor, forall, existential, resolver, provider, scoped => { if !self_.valid(value.a) { return blot_error::Error.type_limit; } },
        function => { if !self_.valid(value.a) || !self_.valid(value.b) { return blot_error::Error.type_limit; } },
        _ => {},
    }
    match value.tag {
        product => { if value.a > values.len || value.b > values.len - value.a { return blot_error::Error.type_limit; } },
        record => { if value.a > values.len || value.b > (values.len - value.a) / 2 { return blot_error::Error.type_limit; } },
        nominal, projection => { if value.c >= values.len || values[value.c] > values.len - value.c - 1 { return blot_error::Error.type_limit; } },
        usage => { if value.b > blot_parse_ast::usagekind_concurrent { return blot_error::Error.type_limit; } },
        _ => {},
    }
    if value.tag == blot_check_types::Tag.projection && values[value.c] >= values.len - value.c - 1 { return blot_error::Error.type_limit; }
    var first = value.a as i64; var count: i64 = 0; var stride: i64 = 1;
    match value.tag { product => { count = value.b; }, record => { count = value.b; first += 1; stride = 2; }, nominal, projection => { count = values[value.c]; first = value.c as i64 + 1; }, _ => {}, }
    for index in 0..count { let error = self_.work.charge(1); if error != blot_error::Error.none { return error; } if !self_.valid(values[first + index * stride]) { return blot_error::Error.type_limit; } } return blot_error::Error.none;
}
fn nominalProperty<S,N>(self_: const NominalStore<S,N>&, value: blot_check_types::Node, mode: Mode) -> bool, Error {
    for nominal in self_.nominals { let error = self_.work.charge(1); if error != blot_error::Error.none { return false, error; } if nominal.identity.unit == value.a && nominal.identity.decl == value.b { if mode == Mode.any { return nominal.has_usage, blot_error::Error.none; } return nominal.affine, blot_error::Error.none; } } return false, blot_error::Error.none;
}
fn nominalShape(store, nominals, node: blot_check_types::Node, work: Work&) -> Error { let context = NominalStore { store, nominals, work , ..}; let error = work.charge(1); if error != blot_error::Error.none { return error; } return shape(context, node); }
fn affine(store, root: Id) -> bool, Error { var work = Work {..}; let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); let context = NominalStore { store, empty, work , ..}; return inspectWithMemo(context, root, Mode.affine, work, null); }
fn borrowed(store, root: Id) -> bool, Error { var work = Work {..}; let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); let context = NominalStore { store, empty, work , ..}; return inspectWithMemo(context, root, Mode.borrow, work, null); }
fn contains(store, root: Id) -> bool, Error { var work = Work {..}; let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); let context = NominalStore { store, empty, work , ..}; return inspectWithMemo(context, root, Mode.any, work, null); }
fn affineNominal(store, nominals, root: Id) -> bool, Error { var work = Work {..}; return affineNominalWork(store, nominals, root, work); }
fn affineNominalWork(store, nominals, root: Id, work: Work&) -> bool, Error { let context = NominalStore { store, nominals, work , ..}; return inspectWithMemo(context, root, Mode.affine, work, null); }
fn containsNominal(store, nominals, root: Id) -> bool, Error { var work = Work {..}; return containsNominalWork(store, nominals, root, work); }
fn containsNominalWork(store, nominals, root: Id, work: Work&) -> bool, Error { let context = NominalStore { store, nominals, work , ..}; return inspectWithMemo(context, root, Mode.any, work, null); }
fn containsNominalMemoWork(store: const blot_check_types::Store&, nominals, root: Id, work: Work&, memo: Memo&) -> bool, Error {
    let epoch = store.mutation_epoch; var same_catalog = memo.nominals.len == nominals.len;
    if same_catalog { for prior, index in memo.nominals { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let nominal = nominals[index]; if prior.identity != nominal.identity || prior.has_usage != nominal.has_usage { same_catalog = false; break; } } }
    if !memo.epoch.present || memo.epoch.value != epoch || !memo.row_epoch.present || memo.row_epoch.value != store.effects.mutation_epoch || !same_catalog || epoch == 0xffffffffffffffff { memo.safe.clear(); }
    memo.epoch = blot_support::some(epoch); memo.row_epoch = blot_support::some(store.effects.mutation_epoch);
    if !same_catalog { memo.nominals.clear(); for nominal in nominals { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } memo.nominals.push(NominalFact { nominal.identity, nominal.has_usage , ..}); } }
    let context = NominalStore { store, nominals, work , ..}; if epoch == 0xffffffffffffffff || store.effects.mutation_epoch == 0xffffffffffffffff { return inspectWithMemo(context, root, Mode.any, work, null); } return inspectWithMemo(context, root, Mode.any, work, memo);
}
struct Pending { ids: Id[4096], slots: u16[8192] = [0; 8192], count: i64 = 0 }
fn add(self_: Pending&, source, raw: Id, budget: Work&, known: Memo?) -> Error {
    if !source.valid(raw) { return blot_error::Error.type_limit; } let id = source.head(raw, 0); if !source.valid(id) { return blot_error::Error.type_limit; }
    { let optional_binding_72 .= known; if optional_binding_72 { let cache .= optional_binding_72; let error = budget.charge(1); if error != blot_error::Error.none { return error; } if ::contains(cache.safe,id) { return blot_error::Error.none; }  } }
    var slot = ((id as u64 * 0x9e3779b1) & (self_.slots.len as u64 - 1)) as i64;
    while true { let error = budget.charge(1); if error != blot_error::Error.none { return error; } let prior = self_.slots[slot]; if prior == 0 { break; } if self_.ids[prior - 1] == id { return blot_error::Error.none; } slot = (slot + 1) & (self_.slots.len - 1); }
    if self_.count == self_.ids.len { return blot_error::Error.type_limit; } self_.ids[self_.count] = id; self_.count += 1; self_.slots[slot] = self_.count as u16; return blot_error::Error.none;
}
fn inspectWithMemo(store, root: Id, mode: Mode, work: Work&, memo: Memo?) -> bool, Error {
    var pending = Pending {..}; let error = pending.add(store, root, work, memo); if error != blot_error::Error.none { return false, error; } var next: i64 = 0;
    while next != pending.count { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let id = pending.ids[next]; next += 1; let node = store.node(id);
        let error = store.shape(node); if error != blot_error::Error.none { return false, error; }
        if mode != Mode.borrow && node.tag == blot_check_types::Tag.nominal { let property, error = store.nominalProperty(node, mode); if error != blot_error::Error.none { return false, error; } if property { return true, blot_error::Error.none; } }
        if mode == Mode.any && (node.tag == blot_check_types::Tag.scoped || node.tag == blot_check_types::Tag.instance_version) { return true, blot_error::Error.none; }
        if node.tag == blot_check_types::Tag.usage { if mode == Mode.any { return true, blot_error::Error.none; } let kind = node.b;
            if mode == Mode.borrow { if kind == blot_parse_ast::usagekind_borrow || kind == blot_parse_ast::usagekind_borrow_mut { return true, blot_error::Error.none; } }
            else if kind == blot_parse_ast::usagekind_unique || kind == blot_parse_ast::usagekind_borrow_mut || kind == blot_parse_ast::usagekind_once { return true, blot_error::Error.none; }
        }

        match node.tag {
            usage, array, list, cursor, forall, existential => { let error=work.charge(1); if error!=blot_error::Error.none {return false,error;} let error=pending.add(store,node.a,work,memo); if error!=blot_error::Error.none {return false,error;} },
            product => { let edges=store.list(blot_check_types::List { node.a, node.b , ..}); let error = work.charge(edges.len); if error != blot_error::Error.none { return false, error; } for edge in edges { let error = pending.add(store, edge, work, memo); if error != blot_error::Error.none { return false, error; } } },
            nominal, projection => { let edges=store.nominalArguments(node); let error = work.charge(edges.len); if error != blot_error::Error.none { return false, error; } for edge in edges { let error = pending.add(store, edge, work, memo); if error != blot_error::Error.none { return false, error; } } },
            function => { if mode == Mode.any { let error = pending.add(store, node.a, work, memo); if error != blot_error::Error.none { return false, error; } let error = pending.add(store, node.b, work, memo); if error != blot_error::Error.none { return false, error; } } },
            record => { for index in 0..node.b { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let error = pending.add(store, store.recordField(node, index).ty, work, memo); if error != blot_error::Error.none { return false, error; } } },
            _ => {},
        }

    }
    { let optional_binding_71 .= memo; if optional_binding_71 { let cache .= optional_binding_71; for index in 0..pending.count { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } cache.safe.insert(pending.ids[index], true); }  } } return false, blot_error::Error.none;
}
struct Walker<E> {
    engine: E, task_views: bool = false, states: State[>..<]&, remaining: i64 = 65536, regions: Id[128], region_count: i64 = 0, returns: ExitFrame? = null, breaks: ExitFrame? = null,
}
fn record<E>(self_: Walker<E>&, frame: ExitFrame&) { frame.seen = true; for &entry, index in frame.joined { if entry.first == 0 { entry.first = self_.states[index].first; } } }
fn charge<E>(self_: Walker<E>&, depth: i64) -> Error { if depth >= 128 || self_.remaining == 0 { return blot_error::Error.type_limit; } self_.remaining -= 1; return blot_error::Error.none; }
fn snapshot<E>(self_: Walker<E>&, destination: StateBuffer&) -> Error { if self_.states.len > self_.remaining { return blot_error::Error.type_limit; } self_.remaining -= self_.states.len; return blot_support_pooled_buffer::append(destination,self_.states[..],state_scratch); }
fn restore<E>(self_: Walker<E>&, states: const State[:]) { self_.states.resize(states.len); for entry, index in states { self_.states[index] = entry; } }
fn state<E>(self_: Walker<E>&, binding: u32) -> State? { for &entry in self_.states { if entry.binding == binding { return entry; } } return null; }
fn introduce<E>(self_: Walker<E>&, binding: u32) -> Error {
    if binding == 0 || self_.state(binding) != null { return blot_error::Error.none; } let affine, error = affineNominal(self_.engine.types, self_.engine.nominals, self_.engine.bindings[binding].ty); if error != blot_error::Error.none { return error; } if !affine { return blot_error::Error.none; }
    if self_.states.len == 4096 { return blot_error::Error.type_limit; } self_.states.push(State { binding , ..}); return blot_error::Error.none;
}
fn use<E>(self_: Walker<E>&, binding: u32, source: AstId) -> Error {
    if binding == 0 { return blot_error::Error.none; } let affine, error = affineNominal(self_.engine.types, self_.engine.nominals, self_.engine.bindings[binding].ty); if error != blot_error::Error.none { return error; } if !affine { return blot_error::Error.none; }
    { let optional_binding_70 .= self_.state(binding); if optional_binding_70 { let entry .= optional_binding_70;
        if entry.loan != 0 { return self_.engine.usageConflict(blot_check_check::Code.borrow_conflict, source, entry.loan, self_.engine.bindings[binding].declaration); }
        if entry.first != 0 { var code = blot_check_check::Code.use_after_move; let ty = self_.engine.types.node(self_.engine.types.head(self_.engine.bindings[binding].ty, 0)); if ty.tag == blot_check_types::Tag.usage && ty.b == blot_parse_ast::usagekind_once { code = blot_check_check::Code.once_reused; }
            if blot_check_task_types::isHandle(self_.engine.types, self_.engine.bindings[binding].ty) { code = blot_check_check::Code.task_handle_consumed; } return self_.engine.usageConflict(code, source, entry.first, self_.engine.bindings[binding].declaration);
        } entry.first = source; return blot_error::Error.none;
     } } return self_.engine.usageDiagnostic(blot_check_check::Code.duplicate_owner, source);
}
recursive fn suite<E>(self_: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    if source == 0 { return Outcome.live, blot_error::Error.none; } let error = self_.charge(depth); if error != blot_error::Error.none { return Outcome.live, error; }
    for child in self_.engine.tree.children(source) { let flow, error = expression(self_, child, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } } return Outcome.live, blot_error::Error.none;
}
recursive fn block_<E>(self_: Walker<E>&, source: AstId, depth: i64)->Outcome, Error {var joined=StateBuffer{..};let flow,error=block_Value(self_,source,depth,joined);blot_support_pooled_buffer::deinit(joined,state_scratch);return flow,error;}
recursive fn block_Value<E>(self_: Walker<E>&, source: AstId, depth: i64,joined:StateBuffer&)->Outcome, Error {
    let error = snapshot(self_, joined); if error != blot_error::Error.none { return Outcome.live, error; }
    var frame = exitFrame(joined.items); var scoped=scopedWalker(self_,frame,self_.breaks); let flow, error = suite(scoped, source, depth + 1); publishWalker(self_,scoped); if error != blot_error::Error.none { return flow, error; } self_.states.resize(joined.items.len);
    if frame.seen { if flow == Outcome.exit { restore(self_, joined.items); } else { for &entry, index in self_.states { if entry.first == 0 { entry.first = joined.items[index].first; } } } return Outcome.live, blot_error::Error.none; } return flow, blot_error::Error.none;
}
fn integer<E>(self_: Walker<E>&, source: AstId) -> blot_support::Option<u32> {
    if source == 0 { return blot_support::none<u32>(); } var id = source; var depth: i64 = 0;
    while self_.engine.tree.node(id).tag == blot_parse_ast::tag_group { if depth == 128 { return blot_support::none<u32>(); } depth += 1; id = self_.engine.tree.node(id).a; }
    let node = self_.engine.tree.node(id); if node.tag != blot_parse_ast::tag_integer { return blot_support::none<u32>(); } return blot_support::some(node.a);
}
fn singleIteration<E>(self_: Walker<E>&, first: AstId, end: AstId) -> bool { let low = integer(self_, first); let high = integer(self_, end); return low.present && high.present && low.value < high.value && high.value - low.value == 1; }
recursive fn pattern<E>(self_: Walker<E>&, source: AstId, depth: i64) -> Error {
    let error = self_.charge(depth); if error != blot_error::Error.none { return error; } let node = self_.engine.tree.node(source);
    if node.tag == blot_parse_ast::tag_pattern_name { return introduce(self_, self_.engine.resolved[source]); }
    if node.tag == blot_parse_ast::tag_pattern_constructor || node.tag == blot_parse_ast::tag_pattern_field { if node.b != 0 { return pattern(self_, node.b, depth + 1); } if node.tag == blot_parse_ast::tag_pattern_field { return introduce(self_, self_.engine.resolved[source]); } }
    else if node.tag == blot_parse_ast::tag_pattern_product || node.tag == blot_parse_ast::tag_pattern_record { for child in self_.engine.tree.children(source) { let error = pattern(self_, child, depth + 1); if error != blot_error::Error.none { return error; } } } return blot_error::Error.none;
}
recursive fn captures<E>(self_: Walker<E>&, source: AstId, owner: AstId, once: bool, found: IdBuffer&, depth: i64)->Error {var children=IdBuffer{..};let error=capturesValue(self_,source,owner,once,found,depth,children);blot_support_pooled_buffer::deinit(children,capture_scratch);return error;}
recursive fn capturesValue<E>(self_: Walker<E>&, source: AstId, owner: AstId, once: bool, found: IdBuffer&, depth: i64,children:IdBuffer&)->Error {
    let error = self_.charge(depth); if error != blot_error::Error.none { return error; } let node = self_.engine.tree.node(source);
    if node.tag == blot_parse_ast::tag_name {
        let binding = self_.engine.resolved[source]; if binding == 0 || self_.engine.bindings[binding].owner == owner || self_.state(binding) == null { return blot_error::Error.none; }
        for prior in found.items { if prior == binding { return blot_error::Error.none; } } let stored=blot_support_pooled_buffer::push(found,binding,capture_scratch); if stored!=blot_error::Error.none {return stored;}
        if !once { return self_.engine.usageDiagnostic(blot_check_check::Code.duplicate_owner, source); } return use(self_, binding, source);
    }
    let collected=captureChildren(self_, source, children); if collected!=blot_error::Error.none {return collected;}
    for child in children.items { let error = captures(self_, child, owner, once, found, depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn captureChildren<E>(self_: Walker<E>&, source: AstId, output: IdBuffer&)->Error {
    let node = self_.engine.tree.node(source);
    match node.tag {
        blot_parse_ast::tag_lambda => { let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_group, blot_parse_ast::tag_field_access, blot_parse_ast::tag_return_stmt, blot_parse_ast::tag_function_return_stmt, blot_parse_ast::tag_yield_stmt, blot_parse_ast::tag_type_witness => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_field, blot_parse_ast::tag_unary, blot_parse_ast::tag_operator_tail => { if node.b != 0 { let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} } },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access, blot_parse_ast::tag_rebind_stmt => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_binary => { let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::push(output,node.c,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_if_expr, blot_parse_ast::tag_if_stmt => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} if node.c != 0 { let stored=blot_support_pooled_buffer::push(output,node.c,capture_scratch); if stored!=blot_error::Error.none {return stored;} } },
        blot_parse_ast::tag_product, blot_parse_ast::tag_record, blot_parse_ast::tag_array, blot_parse_ast::tag_block => { let stored=blot_support_pooled_buffer::append(output,self_.engine.tree.children(source),capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_let_stmt => { let binding = self_.engine.tree.binding(source); let stored=blot_support_pooled_buffer::push(output,binding.value,capture_scratch); if stored!=blot_error::Error.none {return stored;} if binding.fallback != 0 { let stored=blot_support_pooled_buffer::push(output,binding.fallback,capture_scratch); if stored!=blot_error::Error.none {return stored;} } },
        blot_parse_ast::tag_use_stmt, blot_parse_ast::tag_iterator_bind => { let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_infix_chain => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::append(output,self_.engine.tree.list(blot_parse_ast::List { node.b, node.c , ..}),capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_case_expr => {
            let inputs = self_.engine.tree.extra.items[node.a..node.a + 2]; let stored=blot_support_pooled_buffer::append(output,self_.engine.tree.list(blot_parse_ast::List { inputs[0], inputs[1] , ..}),capture_scratch); if stored!=blot_error::Error.none {return stored;}
            for arm in self_.engine.tree.list(blot_parse_ast::List { node.b, node.c , ..}) { let start = self_.engine.tree.node(arm).c; let details = self_.engine.tree.extra.items[start..start + 2]; if details[0] != 0 { let stored=blot_support_pooled_buffer::push(output,details[0],capture_scratch); if stored!=blot_error::Error.none {return stored;} } let stored=blot_support_pooled_buffer::push(output,details[1],capture_scratch); if stored!=blot_error::Error.none {return stored;} }
        },
        blot_parse_ast::tag_if_let_stmt => { let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} for body in self_.engine.tree.extra.items[node.c..node.c + 2] { if body != 0 { let stored=blot_support_pooled_buffer::push(output,body,capture_scratch); if stored!=blot_error::Error.none {return stored;} } } },
        blot_parse_ast::tag_for_stmt => { let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} let end = self_.engine.tree.extra.items[node.c]; if end != 0 { let stored=blot_support_pooled_buffer::push(output,end,capture_scratch); if stored!=blot_error::Error.none {return stored;} } let stored=blot_support_pooled_buffer::push(output,self_.engine.tree.extra.items[node.c + 1],capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_range_stmt => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::push(output,node.b,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::push(output,node.c,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_forever_stmt => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_package_pack => { let stored=blot_support_pooled_buffer::push(output,self_.engine.tree.extra.items[node.c],capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        blot_parse_ast::tag_package_unpack => { let stored=blot_support_pooled_buffer::push(output,node.a,capture_scratch); if stored!=blot_error::Error.none {return stored;} let stored=blot_support_pooled_buffer::push(output,self_.engine.tree.extra.items[node.c + 2],capture_scratch); if stored!=blot_error::Error.none {return stored;} },
        _ => {},
    }
return blot_error::Error.none;}
recursive fn lambda<E>(self_: Walker<E>&, source: AstId, depth: i64)->Error {var captured=IdBuffer{..};var previous=StateBuffer{..};let error=lambdaValue(self_,source,depth,captured,previous);blot_support_pooled_buffer::deinit(previous,state_scratch);blot_support_pooled_buffer::deinit(captured,capture_scratch);return error;}
recursive fn lambdaValue<E>(self_: Walker<E>&, source: AstId, depth: i64,captured:IdBuffer&,previous:StateBuffer&)->Error {
    let node = self_.engine.tree.node(source); let ty = self_.engine.types.node(self_.engine.types.head(self_.engine.expr_types[source], 0));
    if ty.tag == blot_check_types::Tag.usage && ty.b == blot_parse_ast::usagekind_cleanup { if !blot_check_cleanup_contracts::source(self_.engine, source) { let error = self_.engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, source); if error != blot_error::Error.none { return error; } } }
    if blot_check_cleanup_contracts::pureNominal(self_.engine.types, self_.engine.nominals, self_.engine.expr_types[node.a]) { let error = self_.engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, node.a); if error != blot_error::Error.none { return error; } }
    let once = ty.tag == blot_check_types::Tag.usage && ty.b == blot_parse_ast::usagekind_once; let error = captures(self_, node.b, source, once, captured, depth + 1); if error != blot_error::Error.none { return error; }
    let error = snapshot(self_, previous); if error != blot_error::Error.none { return error; }
    for binding in captured.items { { let optional_binding_69 .= self_.state(binding); if optional_binding_69 { let entry .= optional_binding_69; entry.first = 0;  } } }
    var scoped=scopedWalker(self_,null,null);
    var error = introduce(scoped, self_.engine.resolved[node.a]); if error == blot_error::Error.none { let flow, failure = expression(scoped, node.b, depth + 1); error = failure; }
    publishWalker(self_,scoped); restore(self_, previous.items); return error;
}
recursive fn branches<E>(self_: Walker<E>&, left: AstId, right: AstId, suites: bool, depth: i64)->Outcome, Error {var prior=StateBuffer{..};var after=StateBuffer{..};let flow,error=branchesValue(self_,left,right,suites,depth,prior,after);blot_support_pooled_buffer::deinit(after,state_scratch);blot_support_pooled_buffer::deinit(prior,state_scratch);return flow,error;}
recursive fn branchesValue<E>(self_: Walker<E>&, left: AstId, right: AstId, suites: bool, depth: i64,prior:StateBuffer&,after:StateBuffer&)->Outcome, Error {
    let error = snapshot(self_, prior); if error != blot_error::Error.none { return Outcome.live, error; }
    var left_flow = Outcome.live; var right_flow = Outcome.live;
    if suites { let flow, error = suite(self_, left, depth + 1); if error != blot_error::Error.none { return flow, error; } left_flow = flow; }
    else { let flow, error = expression(self_, left, depth + 1); if error != blot_error::Error.none { return flow, error; } left_flow = flow; }
    self_.states.resize(prior.items.len); let error = snapshot(self_, after); if error != blot_error::Error.none { return Outcome.live, error; } restore(self_, prior.items);
    if right != 0 { if suites { let flow, error = suite(self_, right, depth + 1); if error != blot_error::Error.none { return flow, error; } right_flow = flow; } else { let flow, error = expression(self_, right, depth + 1); if error != blot_error::Error.none { return flow, error; } right_flow = flow; } }
    self_.states.resize(prior.items.len); for &entry, index in self_.states { let first = after.items[index]; if right_flow == Outcome.exit { entry = first; } else if left_flow != Outcome.exit && entry.first == 0 { entry.first = first.first; } }
    if left_flow == Outcome.exit && right_flow == Outcome.exit { return Outcome.exit, blot_error::Error.none; } return Outcome.live, blot_error::Error.none;
}
recursive fn cases<E>(self_: Walker<E>&, node: blot_parse_ast::Node, depth: i64)->Outcome, Error {var before=StateBuffer{..};var joined=StateBuffer{..};let flow,error=casesValue(self_,node,depth,before,joined);blot_support_pooled_buffer::deinit(joined,state_scratch);blot_support_pooled_buffer::deinit(before,state_scratch);return flow,error;}
recursive fn casesValue<E>(self_: Walker<E>&, node: blot_parse_ast::Node, depth: i64,before:StateBuffer&,joined:StateBuffer&)->Outcome, Error {
    let inputs = self_.engine.tree.extra.items[node.a..node.a + 2]; for input in self_.engine.tree.list(blot_parse_ast::List { inputs[0], inputs[1] , ..}) { let flow, error = expression(self_, input, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } }
    let error = snapshot(self_, before); if error != blot_error::Error.none { return Outcome.live, error; } let error = snapshot(self_, joined); if error != blot_error::Error.none { return Outcome.live, error; } var live = false;
    for arm_id in self_.engine.tree.list(blot_parse_ast::List { node.b, node.c , ..}) { restore(self_, before.items); let arm = self_.engine.tree.node(arm_id);
        for row in self_.engine.tree.list(blot_parse_ast::List { arm.a, arm.b , ..}) { for pattern_id in self_.engine.tree.children(row) { let error = pattern(self_, pattern_id, depth + 1); if error != blot_error::Error.none { return Outcome.live, error; } } }
        let details = self_.engine.tree.extra.items[arm.c..arm.c + 2];
        if details[0] != 0 { let flow, error = expression(self_, details[0], depth + 1); if error != blot_error::Error.none { return flow, error; } if flow == Outcome.exit { self_.states.resize(before.items.len); continue; }
            for &entry, index in before.items { if entry.first == 0 { entry.first = self_.states[index].first; } }
            for entry in self_.states[before.items.len..] { if entry.first != 0 { let error = self_.engine.usageDiagnostic(blot_check_check::Code.duplicate_owner, details[0]); if error != blot_error::Error.none { return Outcome.live, error; } } }
        }
        let flow, error = expression(self_, details[1], depth + 1); if error != blot_error::Error.none { return flow, error; } self_.states.resize(before.items.len);
        if flow == Outcome.live { live = true; for &entry, index in joined.items { if entry.first == 0 { entry.first = self_.states[index].first; } } }
    } restore(self_, joined.items); if !live { return Outcome.exit, blot_error::Error.none; } return Outcome.live, blot_error::Error.none;
}
fn admitsAffine<E>(self_: Walker<E>&, callee_source: AstId) -> bool, Error {
    var task_head = callee_source;
    for depth in 0..128 { let candidate = self_.engine.tree.node(task_head); if candidate.tag == blot_parse_ast::tag_apply || candidate.tag == blot_parse_ast::tag_group { task_head = candidate.a; continue; }
        if candidate.tag == blot_parse_ast::tag_intrinsic && blot_check_task_types::lookup(self_.engine.pool.get(candidate.a)).present { return true, blot_error::Error.none; } break;
    }
    var source = callee_source; if self_.engine.isSpawnUse(source) { return true, blot_error::Error.none; } while self_.engine.tree.node(source).tag == blot_parse_ast::tag_group { source = self_.engine.tree.node(source).a; }
    let node = self_.engine.tree.node(source); if node.tag == blot_parse_ast::tag_lambda || node.tag == blot_parse_ast::tag_constructor_ref { return true, blot_error::Error.none; }
    let binding = self_.engine.resolved[source]; if binding == 0 { return false, blot_error::Error.none; } let declaration = self_.engine.bindings[binding];
    if declaration.capability_flow == blot_check_capability_flow::Contract.consume_task || declaration.capability_flow == blot_check_capability_flow::Contract.spawn_task { return true, blot_error::Error.none; }
    if declaration.kind == blot_reuse_principal_interface::Kind.parameter { let parameter = self_.engine.tree.parameter(declaration.declaration); var annotation = parameter.annotation; if annotation == 0 { return false, blot_error::Error.none; }
        while self_.engine.tree.node(annotation).tag == blot_parse_ast::tag_group || self_.engine.tree.node(annotation).tag == blot_parse_ast::tag_type_usage || self_.engine.tree.node(annotation).tag == blot_parse_ast::tag_type_forall {
            let wrapper = self_.engine.tree.node(annotation); if wrapper.tag == blot_parse_ast::tag_group { annotation = wrapper.a; } else if wrapper.tag == blot_parse_ast::tag_type_forall { annotation = self_.engine.tree.extra.items[wrapper.c]; } else { annotation = wrapper.b; }
        } let arrow = self_.engine.tree.node(annotation); if arrow.tag != blot_parse_ast::tag_type_function { return false, blot_error::Error.none; } var input = arrow.a; while self_.engine.tree.node(input).tag == blot_parse_ast::tag_group { input = self_.engine.tree.node(input).a; } return self_.engine.tree.node(input).tag == blot_parse_ast::tag_type_usage, blot_error::Error.none;
    }
    var header = self_.engine.types.node(self_.engine.types.head(declaration.ty, 0)); while header.tag == blot_check_types::Tag.usage || header.tag == blot_check_types::Tag.forall { header = self_.engine.types.node(self_.engine.types.head(header.a, 0)); }
    if header.tag != blot_check_types::Tag.function { return false, blot_error::Error.none; } if self_.engine.types.node(header.a).tag == blot_check_types::Tag.usage { return true, blot_error::Error.none; } return affineNominal(self_.engine.types, self_.engine.nominals, header.a);
}
recursive fn inspectRead<E>(self_: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    var operand = source; while self_.engine.tree.node(operand).tag == blot_parse_ast::tag_group { operand = self_.engine.tree.node(operand).a; }
    if self_.engine.tree.node(operand).tag == blot_parse_ast::tag_name { { let optional_binding_68 .= self_.state(self_.engine.resolved[operand]); if optional_binding_68 { let entry .= optional_binding_68;
        if entry.loan != 0 { let error = self_.engine.usageDiagnostic(blot_check_check::Code.borrow_conflict, operand); if error != blot_error::Error.none { return Outcome.live, error; } }
        if entry.first != 0 { let error = self_.engine.usageDiagnostic(blot_check_check::Code.use_after_move, operand); if error != blot_error::Error.none { return Outcome.live, error; } }
     } } return Outcome.live, blot_error::Error.none; } return expression(self_, source, depth + 1);
}
recursive fn taskReadWrite<E>(self_: Walker<E>&, source: AstId, depth: i64) -> bool, Outcome, Error {
    if !self_.task_views || self_.engine.tree.node(source).tag != blot_parse_ast::tag_apply { return false, Outcome.live, blot_error::Error.none; }
    var head = source; var arguments: AstId[3]; var count: i64 = 0;
    while self_.engine.tree.node(head).tag == blot_parse_ast::tag_apply && count < arguments.len { arguments[count] = self_.engine.tree.node(head).b; count += 1; head = self_.engine.tree.node(head).a; }
    if self_.engine.tree.node(head).tag == blot_parse_ast::tag_intrinsic { let operation = blot_check_task_types::lookup(self_.engine.pool.get(self_.engine.tree.node(head).a));
        if operation.present && (operation.value == blot_check_task_types::Op.read || operation.value == blot_check_task_types::Op.write) && count == blot_check_task_types::arity(operation.value) {
            let flow, error = inspectRead(self_, arguments[count - 1], depth); if error != blot_error::Error.none || flow == Outcome.exit { return true, flow, error; }
            var index = count - 1; while index != 0 { index -= 1; let flow, error = expression(self_, arguments[index], depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return true, flow, error; } }
            return true, Outcome.live, blot_error::Error.none;
        }
    } return false, Outcome.live, blot_error::Error.none;
}
recursive fn loanExpression<E>(self_: Walker<E>&, source: AstId, depth: i64) -> bool, Outcome, Error {
    let node = self_.engine.tree.node(source); if node.tag != blot_parse_ast::tag_apply { return false, Outcome.live, blot_error::Error.none; }
    for &loan in self_.engine.usage_loans { if loan.source != source { continue; }
        if loan.acquire != 0 {
            let flow, error = expression(self_, loan.acquire, depth + 1); if error != blot_error::Error.none { return true, flow, error; } let flow, error = expression(self_, loan.release, depth + 1); if error != blot_error::Error.none { return true, flow, error; }
            if loan.callback == 0 { return true, Outcome.live, blot_error::Error.none; } if self_.region_count == self_.regions.len { return true, Outcome.live, blot_error::Error.type_limit; }
            self_.regions[self_.region_count] = loan.region; self_.region_count += 1; let flow, error = expression(self_, loan.callback, depth + 1); self_.region_count -= 1; return true, Outcome.live, error;
        }
        var first = node.a; while self_.engine.tree.node(first).tag == blot_parse_ast::tag_group { first = self_.engine.tree.node(first).a; } var owner = self_.engine.tree.node(first).b; while self_.engine.tree.node(owner).tag == blot_parse_ast::tag_group { owner = self_.engine.tree.node(owner).a; }
        var binding: u32 = 0; if self_.engine.tree.node(owner).tag == blot_parse_ast::tag_name { binding = self_.engine.resolved[owner]; }
        { let optional_binding_67 .= self_.state(binding); if optional_binding_67 { let entry .= optional_binding_67; if entry.first != 0 || entry.loan != 0 { let error = self_.engine.usageDiagnostic(blot_check_check::Code.borrow_conflict, owner); if error != blot_error::Error.none { return true, Outcome.live, error; } } entry.loan = source;  }
        else { let flow, error = expression(self_, owner, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return true, flow, error; } } }
        var error = blot_error::Error.none;
        if self_.region_count == self_.regions.len { error = blot_error::Error.type_limit; }
        else { self_.regions[self_.region_count] = loan.region; self_.region_count += 1; let flow, failure = expression(self_, node.b, depth + 1); error = failure; self_.region_count -= 1; }
        { let optional_binding_66 .= self_.state(binding); if optional_binding_66 { let entry .= optional_binding_66; entry.loan = 0;  } } return true, Outcome.live, error;
    } return false, Outcome.live, blot_error::Error.none;
}
recursive fn expression<E>(self_: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    if source == 0 { return Outcome.live, blot_error::Error.none; } let error = self_.charge(depth); if error != blot_error::Error.none { return Outcome.live, error; } let node = self_.engine.tree.node(source);
    let handled, flow, error = taskReadWrite(self_, source, depth); if handled || error != blot_error::Error.none { return flow, error; }
    let handled, flow, error = loanExpression(self_, source, depth); if handled || error != blot_error::Error.none { return flow, error; }
    match node.tag {
        blot_parse_ast::tag_name, blot_parse_ast::tag_task_region => { let error = use(self_, self_.engine.resolved[source], source); if error != blot_error::Error.none { return Outcome.live, error; } },
        blot_parse_ast::tag_lambda => { let error = lambda(self_, source, depth + 1); if error != blot_error::Error.none { return Outcome.live, error; } },
        blot_parse_ast::tag_group, blot_parse_ast::tag_field_access, blot_parse_ast::tag_type_witness => { return expression(self_, node.a, depth + 1); },
        blot_parse_ast::tag_return_stmt => { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } { let optional_binding_65 .= self_.returns; if optional_binding_65 { let frame .= optional_binding_65; record(self_, frame);  } } return Outcome.exit, blot_error::Error.none; },
        blot_parse_ast::tag_function_return_stmt => { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none { return flow, error; } return Outcome.exit, blot_error::Error.none; },
        blot_parse_ast::tag_break_stmt, blot_parse_ast::tag_continue_stmt => { { let optional_binding_64 .= self_.breaks; if optional_binding_64 { let frame .= optional_binding_64; record(self_, frame);  } } return Outcome.exit, blot_error::Error.none; },
        blot_parse_ast::tag_yield_stmt => { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } },
        blot_parse_ast::tag_field, blot_parse_ast::tag_unary, blot_parse_ast::tag_operator_tail => { if node.b != 0 { let flow, error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } } },
        blot_parse_ast::tag_binary => { let flow, error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } let flow, error = expression(self_, node.c, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access => { return application(self_, source, depth); },
        blot_parse_ast::tag_case_expr => { return cases(self_, node, depth + 1); },
        blot_parse_ast::tag_infix_chain => { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } for tail in self_.engine.tree.list(blot_parse_ast::List { node.b, node.c , ..}) { let flow, error = expression(self_, tail, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } } },
        blot_parse_ast::tag_if_let_stmt => {
            let flow, error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } let before = self_.states.len;
            let error = pattern(self_, node.a, depth + 1); if error != blot_error::Error.none { return Outcome.live, error; } let bodies = self_.engine.tree.extra.items[node.c..node.c + 2];
            let result, error = branches(self_, bodies[0], bodies[1], true, depth + 1); self_.states.resize(before); return result, error;
        },
        blot_parse_ast::tag_request_case => {let flow,error=requestCase(self_,node,depth);if error!=blot_error::Error.none {return flow,error;}},
        blot_parse_ast::tag_if_expr, blot_parse_ast::tag_if_stmt => { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } return branches(self_, node.b, node.c, node.tag == blot_parse_ast::tag_if_stmt, depth + 1); },
        blot_parse_ast::tag_let_stmt => {
            let binding = self_.engine.tree.binding(source); let target = self_.engine.resolved[binding.pattern];
            if target != 0 && blot_check_cleanup_contracts::pureNominal(self_.engine.types, self_.engine.nominals, self_.engine.bindings[target].ty) && !blot_check_cleanup_contracts::source(self_.engine, binding.value) { let error = self_.engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, binding.value); if error != blot_error::Error.none { return Outcome.live, error; } }
            let flow, error = expression(self_, binding.value, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; }
            if binding.fallback != 0 {let flow,error=fallbackSuite(self_,binding.fallback,depth);if error!=blot_error::Error.none {return flow,error;}}
            let error = pattern(self_, binding.pattern, depth + 1); if error != blot_error::Error.none { return Outcome.live, error; }
        },
        blot_parse_ast::tag_use_stmt, blot_parse_ast::tag_iterator_bind, blot_parse_ast::tag_rebind_stmt => {
            let flow, error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } let error = introduce(self_, self_.engine.resolved[source]); if error != blot_error::Error.none { return Outcome.live, error; }
        },
        blot_parse_ast::tag_block => { if node.c != 0 && self_.states.len != 0 { let error = self_.engine.usageDiagnostic(blot_check_check::Code.multiplicity_unknown, source); if error != blot_error::Error.none { return Outcome.live, error; } } return block_(self_, source, depth + 1); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_array, blot_parse_ast::tag_record => { for child in self_.engine.tree.children(source) { let flow, error = expression(self_, child, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } } },
        blot_parse_ast::tag_for_stmt, blot_parse_ast::tag_range_stmt, blot_parse_ast::tag_forever_stmt => { return loopExpression(self_, source, depth); },
        blot_parse_ast::tag_package_pack => { let flow, error = expression(self_, self_.engine.tree.extra.items[node.c], depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } },
        blot_parse_ast::tag_package_unpack => { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } let error = introduce(self_, self_.engine.resolved[source]); if error != blot_error::Error.none { return Outcome.live, error; } return expression(self_, self_.engine.tree.extra.items[node.c + 2], depth + 1); },
        _ => {},
    } return Outcome.live, blot_error::Error.none;
}
recursive fn application<E>(self_: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    let node = self_.engine.tree.node(source); var callee_source = node.a; while self_.engine.tree.node(callee_source).tag == blot_parse_ast::tag_group { callee_source = self_.engine.tree.node(callee_source).a; } let callee_node = self_.engine.tree.node(callee_source);
    if node.tag == blot_parse_ast::tag_apply && callee_node.tag == blot_parse_ast::tag_intrinsic {
        let name = self_.engine.pool.get(callee_node.a);
        if name == "@usage.share" || name == "@resource.release" { return expression(self_, node.b, depth + 1); }
        if name == "@usage.read" || name == "@usage.length" { return inspectRead(self_, node.b, depth); }
    }
    if node.tag == blot_parse_ast::tag_apply { for index in 0..self_.region_count { let footprint, error = self_.engine.usageLoanFootprint(node.b, self_.regions[index]); if error != blot_error::Error.none { return Outcome.live, error; }
        if footprint { let admits, error = admitsAffine(self_, node.a); if error != blot_error::Error.none { return Outcome.live, error; } if !admits { let error = self_.engine.usageDiagnostic(blot_check_check::Code.borrow_escape, node.b); if error != blot_error::Error.none { return Outcome.live, error; } } }
    } }
    let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } let flow, error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; }
    if node.tag == blot_parse_ast::tag_apply {
        let affine, error = affineNominal(self_.engine.types, self_.engine.nominals, self_.engine.expr_types[node.b]); if error != blot_error::Error.none { return Outcome.live, error; } var borrowed_value = false;
        if !affine { let value, error = borrowed(self_.engine.types, self_.engine.expr_types[node.b]); if error != blot_error::Error.none { return Outcome.live, error; } borrowed_value = value; }
        if affine || borrowed_value { var callee = self_.engine.types.node(self_.engine.types.head(self_.engine.expr_types[node.a], 0)); if callee.tag == blot_check_types::Tag.usage { callee = self_.engine.types.node(self_.engine.types.head(callee.a, 0)); }
            var admits = false; if callee.tag == blot_check_types::Tag.function { let value, error = admitsAffine(self_, node.a); if error != blot_error::Error.none { return Outcome.live, error; } admits = value; }
            if !admits { let error = self_.engine.usageDiagnostic(blot_check_check::Code.multiplicity_unknown, source); if error != blot_error::Error.none { return Outcome.live, error; } }
        }
    } return Outcome.live, blot_error::Error.none;
}
recursive fn loopExpression<E>(self_: Walker<E>&, source: AstId, depth: i64)->Outcome, Error {var prior=StateBuffer{..};var exits=StateBuffer{..};let flow,error=loopExpressionValue(self_,source,depth,prior,exits);blot_support_pooled_buffer::deinit(exits,state_scratch);blot_support_pooled_buffer::deinit(prior,state_scratch);return flow,error;}
recursive fn loopExpressionValue<E>(self_: Walker<E>&, source: AstId, depth: i64,prior:StateBuffer&,exits:StateBuffer&)->Outcome, Error {
    let node = self_.engine.tree.node(source);
    if node.tag == blot_parse_ast::tag_range_stmt { let flow, error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } }
    if node.tag != blot_parse_ast::tag_forever_stmt { let flow, error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } }
    if node.tag == blot_parse_ast::tag_for_stmt { let end = self_.engine.tree.extra.items[node.c]; if end != 0 { let flow, error = expression(self_, end, depth + 1); if error != blot_error::Error.none || flow == Outcome.exit { return flow, error; } } }
    var single = false; if node.tag == blot_parse_ast::tag_range_stmt { single = singleIteration(self_, node.a, node.b); } if node.tag == blot_parse_ast::tag_for_stmt { single = singleIteration(self_, node.b, self_.engine.tree.extra.items[node.c]); }
    let error = snapshot(self_, prior); if error != blot_error::Error.none { return Outcome.live, error; } let error = snapshot(self_, exits); if error != blot_error::Error.none { return Outcome.live, error; }
    var frame = exitFrame(exits.items); var scoped=scopedWalker(self_,self_.returns,frame); let flow, error = loopBody(scoped, source, node, prior.items, frame, single, depth); publishWalker(self_,scoped); if error != blot_error::Error.none { return flow, error; } restore(self_, exits.items);
    if (node.tag == blot_parse_ast::tag_forever_stmt || single) && !frame.seen { return Outcome.exit, blot_error::Error.none; } return Outcome.live, blot_error::Error.none;
}
recursive fn loopBody<E>(self_: Walker<E>&, source: AstId, node: blot_parse_ast::Node, prior: const State[:], frame: ExitFrame&, single: bool, depth: i64) -> Outcome, Error {
    if node.tag == blot_parse_ast::tag_for_stmt { let error = pattern(self_, node.a, depth + 1); if error != blot_error::Error.none { return Outcome.live, error; } }
    var body = node.a; if node.tag == blot_parse_ast::tag_range_stmt { body = node.c; } if node.tag == blot_parse_ast::tag_for_stmt { body = self_.engine.tree.extra.items[node.c + 1]; }
    let flow, error = suite(self_, body, depth + 1); if error != blot_error::Error.none { return flow, error; } self_.states.resize(prior.len);
    if flow == Outcome.live && !single { for entry, index in self_.states { if entry.first != prior[index].first { let error = self_.engine.usageDiagnostic(blot_check_check::Code.once_reused, source); if error != blot_error::Error.none { return flow, error; } break; } } }
    if flow == Outcome.live && single { record(self_, frame); } return flow, blot_error::Error.none;
}
fn validate<E>(engine: E) -> Error {
    var states: State[>..<] = []; let read_symbol,read_present=engine.pool.lookup("@task.read");var task_views=read_present;if !task_views {let write_symbol,write_present=engine.pool.lookup("@task.write");task_views=write_present;}var walker = Walker<E> { engine: engine, states: states, task_views: task_views , ..};
    for root in engine.tree.roots.items { if engine.tree.node(root).tag != blot_parse_ast::tag_value_decl { continue; } walker.states.clear(); walker.remaining = 65536; let binding = engine.resolved[root]; let body = engine.tree.value_decl(root).body;
        if binding != 0 && blot_check_cleanup_contracts::pureNominal(engine.types, engine.nominals, engine.bindings[binding].ty) && !blot_check_cleanup_contracts::source(engine, body) { let error = engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, body); if error != blot_error::Error.none { return error; } }
        let flow, error = expression(walker, body, 0); if error == blot_error::Error.type_limit { let error = engine.usageDiagnostic(blot_check_check::Code.usage_analysis_limit, root); if error != blot_error::Error.none { return error; } continue; } if error != blot_error::Error.none { return error; }
    } return blot_error::Error.none;
}

fn outcomeCode(value: Outcome) -> u32 {
    match value {
        live => { return 0; },
        exit => { return 1; },
    }
}
fn outcomeFromCode(code: u32) -> Outcome, blot_error::Error {
    match code {
        0 => { return Outcome.live, blot_error::Error.none; },
        1 => { return Outcome.exit, blot_error::Error.none; },
        _ => { return Outcome.live, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_usage_check::Outcome, right: blot_check_usage_check::Outcome) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_usage_check::Outcome) { blot_structural::hash(sink, blot_check_usage_check::outcomeCode(value) as! u8); }
fn modeCode(value: Mode) -> u32 {
    match value {
        affine => { return 0; },
        any => { return 1; },
        borrow => { return 2; },
    }
}
fn modeFromCode(code: u32) -> Mode, blot_error::Error {
    match code {
        0 => { return Mode.affine, blot_error::Error.none; },
        1 => { return Mode.any, blot_error::Error.none; },
        2 => { return Mode.borrow, blot_error::Error.none; },
        _ => { return Mode.affine, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_usage_check::Mode, right: blot_check_usage_check::Mode) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_usage_check::Mode) { blot_structural::hash(sink, blot_check_usage_check::modeCode(value) as! u8); }





import dictionary;
struct PooledMemo {safe:blot_support_pooled_map::Map<Id,bool>   = blot_support_pooled_map::Map<Id,bool>{..},epoch:blot_support::Option<u64>   = blot_support::none<u64>(),row_epoch:blot_support::Option<u64>   = blot_support::none<u64>(),nominals:blot_support_pooled_buffer::Buffer<NominalFact>   = blot_support_pooled_buffer::Buffer<NominalFact>{..}}
reusable[] var pooled_safe_slots:dictionary_slot<Id,bool>[>..];
reusable[] var pooled_nominal_facts:NominalFact[>..];
fn deinit(self_:PooledMemo&) {blot_support_pooled_map::deinit(self_.safe,pooled_safe_slots);blot_support_pooled_buffer::deinit(self_.nominals,pooled_nominal_facts);}
fn containsNominalMemoWork(store: const blot_check_types::Store&, nominals, root: Id, work: Work&, memo: PooledMemo&) -> bool, Error {
    let epoch = store.mutation_epoch; var same_catalog = memo.nominals.items.len == nominals.len;
    if same_catalog { for prior, index in memo.nominals.items { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let nominal = nominals[index]; if prior.identity != nominal.identity || prior.has_usage != nominal.has_usage { same_catalog = false; break; } } }
    if !memo.epoch.present || memo.epoch.value != epoch || !memo.row_epoch.present || memo.row_epoch.value != store.effects.mutation_epoch || !same_catalog || epoch == 0xffffffffffffffff { memo.safe.clear(); }
    memo.epoch = blot_support::some(epoch); memo.row_epoch = blot_support::some(store.effects.mutation_epoch);
    if !same_catalog { memo.nominals.clear(); for nominal in nominals { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let append_error=blot_support_pooled_buffer::push(memo.nominals,NominalFact { nominal.identity, nominal.has_usage , ..},pooled_nominal_facts); if append_error!=blot_error::Error.none {return false,append_error;} } }
    let context = NominalStore { store, nominals, work , ..}; if epoch == 0xffffffffffffffff || store.effects.mutation_epoch == 0xffffffffffffffff { return inspectWithPooledMemo(context, root, Mode.any, work, null); } return inspectWithPooledMemo(context, root, Mode.any, work, memo);
}
fn addPooled(self_: Pending&, source, raw: Id, budget: Work&, known: PooledMemo?) -> Error {
    if !source.valid(raw) { return blot_error::Error.type_limit; } let id = source.head(raw, 0); if !source.valid(id) { return blot_error::Error.type_limit; }
    { let optional_binding_72 .= known; if optional_binding_72 { let cache .= optional_binding_72; let error = budget.charge(1); if error != blot_error::Error.none { return error; } if blot_support_pooled_map::contains(cache.safe,id) { return blot_error::Error.none; }  } }
    var slot = ((id as u64 * 0x9e3779b1) & (self_.slots.len as u64 - 1)) as i64;
    while true { let error = budget.charge(1); if error != blot_error::Error.none { return error; } let prior = self_.slots[slot]; if prior == 0 { break; } if self_.ids[prior - 1] == id { return blot_error::Error.none; } slot = (slot + 1) & (self_.slots.len - 1); }
    if self_.count == self_.ids.len { return blot_error::Error.type_limit; } self_.ids[self_.count] = id; self_.count += 1; self_.slots[slot] = self_.count as u16; return blot_error::Error.none;
}
fn inspectWithPooledMemo(store, root: Id, mode: Mode, work: Work&, memo: PooledMemo?) -> bool, Error {
    var pending = Pending {..}; let error = pending.addPooled(store, root, work, memo); if error != blot_error::Error.none { return false, error; } var next: i64 = 0;
    while next != pending.count { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let id = pending.ids[next]; next += 1; let node = store.node(id);
        let error = store.shape(node); if error != blot_error::Error.none { return false, error; }
        if mode != Mode.borrow && node.tag == blot_check_types::Tag.nominal { let property, error = store.nominalProperty(node, mode); if error != blot_error::Error.none { return false, error; } if property { return true, blot_error::Error.none; } }
        if mode == Mode.any && (node.tag == blot_check_types::Tag.scoped || node.tag == blot_check_types::Tag.instance_version) { return true, blot_error::Error.none; }
        if node.tag == blot_check_types::Tag.usage { if mode == Mode.any { return true, blot_error::Error.none; } let kind = node.b;
            if mode == Mode.borrow { if kind == blot_parse_ast::usagekind_borrow || kind == blot_parse_ast::usagekind_borrow_mut { return true, blot_error::Error.none; } }
            else if kind == blot_parse_ast::usagekind_unique || kind == blot_parse_ast::usagekind_borrow_mut || kind == blot_parse_ast::usagekind_once { return true, blot_error::Error.none; }
        }

        match node.tag {
            usage, array, list, cursor, forall, existential => { let error=work.charge(1); if error!=blot_error::Error.none {return false,error;} let error=pending.addPooled(store,node.a,work,memo); if error!=blot_error::Error.none {return false,error;} },
            product => { let edges=store.list(blot_check_types::List { node.a, node.b , ..}); let error = work.charge(edges.len); if error != blot_error::Error.none { return false, error; } for edge in edges { let error = pending.addPooled(store, edge, work, memo); if error != blot_error::Error.none { return false, error; } } },
            nominal, projection => { let edges=store.nominalArguments(node); let error = work.charge(edges.len); if error != blot_error::Error.none { return false, error; } for edge in edges { let error = pending.addPooled(store, edge, work, memo); if error != blot_error::Error.none { return false, error; } } },
            function => { if mode == Mode.any { let error = pending.addPooled(store, node.a, work, memo); if error != blot_error::Error.none { return false, error; } let error = pending.addPooled(store, node.b, work, memo); if error != blot_error::Error.none { return false, error; } } },
            record => { for index in 0..node.b { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } let error = pending.addPooled(store, store.recordField(node, index).ty, work, memo); if error != blot_error::Error.none { return false, error; } } },
            _ => {},
        }

    }
    { let optional_binding_71 .= memo; if optional_binding_71 { let cache .= optional_binding_71; for index in 0..pending.count { let error = work.charge(1); if error != blot_error::Error.none { return false, error; } blot_support_pooled_map::insert(cache.safe,pending.ids[index],true,pooled_safe_slots); }  } } return false, blot_error::Error.none;
}

fn exitFrame(joined:State[:])->ExitFrame {return ExitFrame{joined:joined,..};}
fn scopedWalker<E>(parent:const Walker<E>&,returns:ExitFrame?,breaks:ExitFrame?)->Walker<E> {return Walker<E>{engine:parent.engine,task_views:parent.task_views,states:parent.states,remaining:parent.remaining,regions:parent.regions,region_count:parent.region_count,returns:returns,breaks:breaks,..};}
fn publishWalker<E>(target:Walker<E>&,source:const Walker<E>&) {target.task_views=source.task_views;target.remaining=source.remaining;target.regions=source.regions;target.region_count=source.region_count;}

recursive fn requestCase<E>(self_:Walker<E>&,node:blot_parse_ast::Node,depth:i64)->Outcome, Error {var prior=StateBuffer{..};let flow,error=requestCaseValue(self_,node,depth,prior);blot_support_pooled_buffer::deinit(prior,state_scratch);return flow,error;}
recursive fn requestCaseValue<E>(self_:Walker<E>&,node:blot_parse_ast::Node,depth:i64,prior:StateBuffer&)->Outcome, Error {
            let error = snapshot(self_, prior); if error != blot_error::Error.none { return Outcome.live, error; }
            for arm_id in self_.engine.tree.list(blot_parse_ast::List { node.b, node.c , ..}) { restore(self_, prior.items); let arm = self_.engine.tree.node(arm_id); if arm.b != 0 { let error = pattern(self_, arm.b, depth + 1); if error != blot_error::Error.none { return Outcome.live, error; } }
                let flow, error = suite(self_, arm.c, depth + 1); if error != blot_error::Error.none { return flow, error; } self_.states.resize(prior.items.len);
                for after, index in self_.states { let before = prior.items[index]; if after.first != before.first || after.loan != before.loan { let error = self_.engine.usageDiagnostic(blot_check_check::Code.multiplicity_unknown, arm_id); if error != blot_error::Error.none { return Outcome.live, error; } } }
            } restore(self_, prior.items);
        return Outcome.live,blot_error::Error.none;}

recursive fn fallbackSuite<E>(self_:Walker<E>&,source:AstId,depth:i64)->Outcome, Error {var prior=StateBuffer{..};let flow,error=fallbackSuiteValue(self_,source,depth,prior);blot_support_pooled_buffer::deinit(prior,state_scratch);return flow,error;}
recursive fn fallbackSuiteValue<E>(self_:Walker<E>&,source:AstId,depth:i64,prior:StateBuffer&)->Outcome, Error {let error=snapshot(self_,prior);if error!=blot_error::Error.none {return Outcome.live,error;}let flow,error=suite(self_,source,depth+1);restore(self_,prior.items);return flow,error;}
