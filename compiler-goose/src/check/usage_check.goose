// Affine moves follow resolved binding versions and exact lexical owners.
namespace blot_check_usage_check;
import support.error;
import support.option;
import support.structural;
import .types;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type Tag = blot_check_types::Tag;
type AstId = blot_parse_ast::Id;
struct State { binding: u32, first: AstId = 0, loan: AstId = 0 }
enum Outcome { live, exit }
struct ExitFrame { joined: State[:], seen: bool = false }
struct Work { remaining: i64 = 65536 }
fn charge(self: Work&, amount: i64) -> Error { if amount > self.remaining { return Error.type_limit; } self.remaining -= amount; return Error.none; }
struct NominalFact { identity: blot_check_types::NominalIdentity, has_usage: bool }
struct Memo { safe: dictionary<Id,bool>&, epoch: blot_support::Option<u64> = blot_support::none<u64>(), row_epoch: blot_support::Option<u64> = blot_support::none<u64>(), nominals: NominalFact[>..<]& }
fn initMemo(safe: dictionary<Id,bool>&, nominals: NominalFact[>..<]&) -> Memo { return Memo { safe, nominals: nominals }; }
fn deinit(self: Memo&) { self.safe.clear(); self.nominals.clear(); }
enum Mode { affine, any, borrow }
struct NominalStore<S,N> { store: S, nominals: N, work: Work& }
fn head<S,N>(self: const NominalStore<S,N>&, id: Id, cursor: u32) -> Id { return self.store.head(id, cursor); }
fn node<S,N>(self: const NominalStore<S,N>&, id: Id) -> blot_check_types::Node { return self.store.node(id); }
fn list<S,N>(self: const NominalStore<S,N>&, values: blot_check_types::List) -> const Id[:] { return self.store.list(values); }
fn recordField<S,N>(self: const NominalStore<S,N>&, value: blot_check_types::Node, index: i64) -> blot_check_types::Field { return self.store.recordField(value, index); }
fn nominalArguments<S,N>(self: const NominalStore<S,N>&, value: blot_check_types::Node) -> const Id[:] { return self.store.nominalArguments(value); }
fn valid<S,N>(self: const NominalStore<S,N>&, id: Id) -> bool { return id < self.store.nodes.len; }
fn shape<S,N>(self: const NominalStore<S,N>&, value: blot_check_types::Node) -> Error {
    let values = self.store.extra;
    match value.tag {
        Tag.usage, Tag.array, Tag.list, Tag.cursor, Tag.forall, Tag.existential, Tag.resolver, Tag.provider, Tag.scoped => { if !self.valid(value.a) { return Error.type_limit; } },
        Tag.function => { if !self.valid(value.a) || !self.valid(value.b) { return Error.type_limit; } },
        _ => {},
    }
    match value.tag {
        Tag.product => { if value.a > values.len || value.b > values.len - value.a { return Error.type_limit; } },
        Tag.record => { if value.a > values.len || value.b > (values.len - value.a) / 2 { return Error.type_limit; } },
        Tag.nominal, Tag.projection => { if value.c >= values.len || values[value.c] > values.len - value.c - 1 { return Error.type_limit; } },
        Tag.usage => { if value.b > blot_parse_ast::usagekind_concurrent { return Error.type_limit; } },
        _ => {},
    }
    if value.tag == Tag.projection && values[value.c] >= values.len - value.c - 1 { return Error.type_limit; }
    var first = value.a as i64; var count: i64 = 0; var stride: i64 = 1;
    match value.tag { Tag.product => { count = value.b; }, Tag.record => { count = value.b; first += 1; stride = 2; }, Tag.nominal, Tag.projection => { count = values[value.c]; first = value.c as i64 + 1; }, _ => {}, }
    for index in 0..count { let error = self.work.charge(1); if error != Error.none { return error; } if !self.valid(values[first + index * stride]) { return Error.type_limit; } } return Error.none;
}
fn nominalProperty<S,N>(self: const NominalStore<S,N>&, value: blot_check_types::Node, mode: Mode) -> bool, Error {
    for nominal in self.nominals { let error = self.work.charge(1); if error != Error.none { return false, error; } if nominal.identity.unit == value.a && nominal.identity.decl == value.b { if mode == Mode.any { return nominal.has_usage, Error.none; } return nominal.affine, Error.none; } } return false, Error.none;
}
fn nominalShape(store, nominals, node: blot_check_types::Node, work: Work&) -> Error { let context = NominalStore { store, nominals, work }; let error = work.charge(1); if error != Error.none { return error; } return shape(context, node); }
fn affine(store, root: Id) -> bool, Error { var work = Work {}; let empty: const blot_check_core::Nominal[:] = []; let context = NominalStore { store, empty, work }; return inspectWithMemo(context, root, Mode.affine, work, null); }
fn borrowed(store, root: Id) -> bool, Error { var work = Work {}; let empty: const blot_check_core::Nominal[:] = []; let context = NominalStore { store, empty, work }; return inspectWithMemo(context, root, Mode.borrow, work, null); }
fn contains(store, root: Id) -> bool, Error { var work = Work {}; let empty: const blot_check_core::Nominal[:] = []; let context = NominalStore { store, empty, work }; return inspectWithMemo(context, root, Mode.any, work, null); }
fn affineNominal(store, nominals, root: Id) -> bool, Error { var work = Work {}; return affineNominalWork(store, nominals, root, work); }
fn affineNominalWork(store, nominals, root: Id, work: Work&) -> bool, Error { let context = NominalStore { store, nominals, work }; return inspectWithMemo(context, root, Mode.affine, work, null); }
fn containsNominal(store, nominals, root: Id) -> bool, Error { var work = Work {}; return containsNominalWork(store, nominals, root, work); }
fn containsNominalWork(store, nominals, root: Id, work: Work&) -> bool, Error { let context = NominalStore { store, nominals, work }; return inspectWithMemo(context, root, Mode.any, work, null); }
fn containsNominalMemoWork(store: const blot_check_types::Store&, nominals, root: Id, work: Work&, memo: Memo&) -> bool, Error {
    let epoch = store.mutation_epoch; var same_catalog = memo.nominals.len == nominals.len;
    if same_catalog { for prior, index in memo.nominals { let error = work.charge(1); if error != Error.none { return false, error; } let nominal = nominals[index]; if prior.identity != nominal.identity || prior.has_usage != nominal.has_usage { same_catalog = false; break; } } }
    if !memo.epoch.present || memo.epoch.value != epoch || !memo.row_epoch.present || memo.row_epoch.value != store.effects.mutation_epoch || !same_catalog || epoch == 0xffffffffffffffff { memo.safe.clear(); }
    memo.epoch = blot_support::some(epoch); memo.row_epoch = blot_support::some(store.effects.mutation_epoch);
    if !same_catalog { memo.nominals.clear(); for nominal in nominals { let error = work.charge(1); if error != Error.none { return false, error; } memo.nominals += NominalFact { nominal.identity, nominal.has_usage }; } }
    let context = NominalStore { store, nominals, work }; if epoch == 0xffffffffffffffff || store.effects.mutation_epoch == 0xffffffffffffffff { return inspectWithMemo(context, root, Mode.any, work, null); } return inspectWithMemo(context, root, Mode.any, work, memo);
}
struct Pending { ids: Id[4096], slots: u16[8192] = [0; 8192], count: i64 = 0 }
fn add(self: Pending&, source, raw: Id, budget: Work&, known: Memo?) -> Error {
    if !source.valid(raw) { return Error.type_limit; } let id = source.head(raw, 0); if !source.valid(id) { return Error.type_limit; }
    { let optional_binding_72 .= known; if optional_binding_72 { let cache .= optional_binding_72; let error = budget.charge(1); if error != Error.none { return error; } if cache.safe.contains(id) { return Error.none; }  } }
    var slot = ((id as u64 *% 0x9e3779b1) & (self.slots.len as u64 - 1)) as i64;
    while true { let error = budget.charge(1); if error != Error.none { return error; } let prior = self.slots[slot]; if prior == 0 { break; } if self.ids[prior - 1] == id { return Error.none; } slot = (slot + 1) & (self.slots.len - 1); }
    if self.count == self.ids.len { return Error.type_limit; } self.ids[self.count] = id; self.count += 1; self.slots[slot] = self.count as u16; return Error.none;
}
fn inspectWithMemo(store, root: Id, mode: Mode, work: Work&, memo: Memo?) -> bool, Error {
    var pending = Pending {}; let error = pending.add(store, root, work, memo); if error != Error.none { return false, error; } var next: i64 = 0;
    while next != pending.count { let error = work.charge(1); if error != Error.none { return false, error; } let id = pending.ids[next]; next += 1; let node = store.node(id);
        let error = store.shape(node); if error != Error.none { return false, error; }
        if mode != Mode.borrow && node.tag == Tag.nominal { let property, error = store.nominalProperty(node, mode); if error != Error.none { return false, error; } if property { return true, Error.none; } }
        if mode == Mode.any && (node.tag == Tag.scoped || node.tag == Tag.instance_version) { return true, Error.none; }
        if node.tag == Tag.usage { if mode == Mode.any { return true, Error.none; } let kind = node.b;
            if mode == Mode.borrow { if kind == blot_parse_ast::usagekind_borrow || kind == blot_parse_ast::usagekind_borrow_mut { return true, Error.none; } }
            else if kind == blot_parse_ast::usagekind_unique || kind == blot_parse_ast::usagekind_borrow_mut || kind == blot_parse_ast::usagekind_once { return true, Error.none; }
        }
        var child: Id[1] = [node.a]; var edges: const Id[:] = [];
        match node.tag {
            Tag.usage, Tag.array, Tag.list, Tag.cursor, Tag.forall, Tag.existential => { edges = child; },
            Tag.product => { edges = store.list(blot_check_types::List { node.a, node.b }); },
            Tag.nominal, Tag.projection => { edges = store.nominalArguments(node); },
            Tag.function => { if mode == Mode.any { let error = pending.add(store, node.a, work, memo); if error != Error.none { return false, error; } let error = pending.add(store, node.b, work, memo); if error != Error.none { return false, error; } } },
            Tag.record => { for index in 0..node.b { let error = work.charge(1); if error != Error.none { return false, error; } let error = pending.add(store, store.recordField(node, index).ty, work, memo); if error != Error.none { return false, error; } } },
            _ => {},
        }
        let error = work.charge(edges.len); if error != Error.none { return false, error; } for edge in edges { let error = pending.add(store, edge, work, memo); if error != Error.none { return false, error; } }
    }
    { let optional_binding_71 .= memo; if optional_binding_71 { let cache .= optional_binding_71; for index in 0..pending.count { let error = work.charge(1); if error != Error.none { return false, error; } cache.safe.insert(pending.ids[index], true); }  } } return false, Error.none;
}
struct Walker<E> {
    engine: E, task_views: bool = false, states: State[>..<]&, remaining: i64 = 65536, regions: Id[128], region_count: i64 = 0, returns: ExitFrame? = null, breaks: ExitFrame? = null,
}
fn record<E>(self: Walker<E>&, frame: ExitFrame&) { frame.seen = true; for &entry, index in frame.joined { if entry.first == 0 { entry.first = self.states[index].first; } } }
fn charge<E>(self: Walker<E>&, depth: i64) -> Error { if depth >= 128 || self.remaining == 0 { return Error.type_limit; } self.remaining -= 1; return Error.none; }
fn snapshot<E>(self: Walker<E>&, destination: State[>..]&) -> Error { if self.states.len > self.remaining { return Error.type_limit; } self.remaining -= self.states.len; destination += self.states[:]; return Error.none; }
fn restore<E>(self: Walker<E>&, states: const State[:]) { self.states.resize(states.len); for entry, index in states { self.states[index] = entry; } }
fn state<E>(self: Walker<E>&, binding: u32) -> State? { for &entry in self.states { if entry.binding == binding { return entry; } } return null; }
fn introduce<E>(self: Walker<E>&, binding: u32) -> Error {
    if binding == 0 || self.state(binding) != null { return Error.none; } let affine, error = affineNominal(self.engine.types, self.engine.nominals, self.engine.bindings[binding].ty); if error != Error.none { return error; } if !affine { return Error.none; }
    if self.states.len == 4096 { return Error.type_limit; } self.states += State { binding }; return Error.none;
}
fn use<E>(self: Walker<E>&, binding: u32, source: AstId) -> Error {
    if binding == 0 { return Error.none; } let affine, error = affineNominal(self.engine.types, self.engine.nominals, self.engine.bindings[binding].ty); if error != Error.none { return error; } if !affine { return Error.none; }
    { let optional_binding_70 .= self.state(binding); if optional_binding_70 { let entry .= optional_binding_70;
        if entry.loan != 0 { return self.engine.usageConflict(blot_check_check::Code.borrow_conflict, source, entry.loan, self.engine.bindings[binding].declaration); }
        if entry.first != 0 { var code = blot_check_check::Code.use_after_move; let ty = self.engine.types.node(self.engine.types.head(self.engine.bindings[binding].ty, 0)); if ty.tag == Tag.usage && ty.b == blot_parse_ast::usagekind_once { code = blot_check_check::Code.once_reused; }
            if blot_check_task_types::isHandle(self.engine.types, self.engine.bindings[binding].ty) { code = blot_check_check::Code.task_handle_consumed; } return self.engine.usageConflict(code, source, entry.first, self.engine.bindings[binding].declaration);
        } entry.first = source; return Error.none;
     } } return self.engine.usageDiagnostic(blot_check_check::Code.duplicate_owner, source);
}
recursive fn suite<E>(self: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    if source == 0 { return Outcome.live, Error.none; } let error = self.charge(depth); if error != Error.none { return Outcome.live, error; }
    for child in self.engine.tree.children(source) { let flow, error = expression(self, child, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } } return Outcome.live, Error.none;
}
fn block<E>(self: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    var joined: State[>..] = []; let error = snapshot(self, joined); if error != Error.none { return Outcome.live, error; }
    var frame = ExitFrame { joined }; let outer = self.returns; self.returns .= frame; let flow, error = suite(self, source, depth + 1); self.returns .= outer; if error != Error.none { return flow, error; } self.states.resize(joined.len);
    if frame.seen { if flow == Outcome.exit { restore(self, joined); } else { for &entry, index in self.states { if entry.first == 0 { entry.first = joined[index].first; } } } return Outcome.live, Error.none; } return flow, Error.none;
}
fn integer<E>(self: Walker<E>&, source: AstId) -> blot_support::Option<u32> {
    if source == 0 { return blot_support::none<u32>(); } var id = source; var depth: i64 = 0;
    while self.engine.tree.node(id).tag == blot_parse_ast::tag_group { if depth == 128 { return blot_support::none<u32>(); } depth += 1; id = self.engine.tree.node(id).a; }
    let node = self.engine.tree.node(id); if node.tag != blot_parse_ast::tag_integer { return blot_support::none<u32>(); } return blot_support::some(node.a);
}
fn singleIteration<E>(self: Walker<E>&, first: AstId, end: AstId) -> bool { let low = integer(self, first); let high = integer(self, end); return low.present && high.present && low.value < high.value && high.value - low.value == 1; }
recursive fn pattern<E>(self: Walker<E>&, source: AstId, depth: i64) -> Error {
    let error = self.charge(depth); if error != Error.none { return error; } let node = self.engine.tree.node(source);
    if node.tag == blot_parse_ast::tag_pattern_name { return introduce(self, self.engine.resolved[source]); }
    if node.tag == blot_parse_ast::tag_pattern_constructor || node.tag == blot_parse_ast::tag_pattern_field { if node.b != 0 { return pattern(self, node.b, depth + 1); } if node.tag == blot_parse_ast::tag_pattern_field { return introduce(self, self.engine.resolved[source]); } }
    else if node.tag == blot_parse_ast::tag_pattern_product || node.tag == blot_parse_ast::tag_pattern_record { for child in self.engine.tree.children(source) { let error = pattern(self, child, depth + 1); if error != Error.none { return error; } } } return Error.none;
}
recursive fn captures<E>(self: Walker<E>&, source: AstId, owner: AstId, once: bool, found: u32[>..]&, depth: i64) -> Error {
    let error = self.charge(depth); if error != Error.none { return error; } let node = self.engine.tree.node(source);
    if node.tag == blot_parse_ast::tag_name {
        let binding = self.engine.resolved[source]; if binding == 0 || self.engine.bindings[binding].owner == owner || self.state(binding) == null { return Error.none; }
        for prior in found { if prior == binding { return Error.none; } } found += binding;
        if !once { return self.engine.usageDiagnostic(blot_check_check::Code.duplicate_owner, source); } return use(self, binding, source);
    }
    var children: AstId[>..] = []; captureChildren(self, source, children);
    for child in children { let error = captures(self, child, owner, once, found, depth + 1); if error != Error.none { return error; } } return Error.none;
}
fn captureChildren<E>(self: Walker<E>&, source: AstId, output: AstId[>..]&) {
    let node = self.engine.tree.node(source);
    match node.tag {
        blot_parse_ast::tag_lambda => { output += node.b; },
        blot_parse_ast::tag_group, blot_parse_ast::tag_field_access, blot_parse_ast::tag_return_stmt, blot_parse_ast::tag_function_return_stmt, blot_parse_ast::tag_yield_stmt, blot_parse_ast::tag_type_witness => { output += node.a; },
        blot_parse_ast::tag_field, blot_parse_ast::tag_unary, blot_parse_ast::tag_operator_tail => { if node.b != 0 { output += node.b; } },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access, blot_parse_ast::tag_rebind_stmt => { output += node.a; output += node.b; },
        blot_parse_ast::tag_binary => { output += node.b; output += node.c; },
        blot_parse_ast::tag_if_expr, blot_parse_ast::tag_if_stmt => { output += node.a; output += node.b; if node.c != 0 { output += node.c; } },
        blot_parse_ast::tag_product, blot_parse_ast::tag_record, blot_parse_ast::tag_array, blot_parse_ast::tag_block => { output += self.engine.tree.children(source); },
        blot_parse_ast::tag_let_stmt => { let binding = self.engine.tree.binding(source); output += binding.value; if binding.fallback != 0 { output += binding.fallback; } },
        blot_parse_ast::tag_use_stmt, blot_parse_ast::tag_iterator_bind => { output += node.b; },
        blot_parse_ast::tag_infix_chain => { output += node.a; output += self.engine.tree.list(blot_parse_ast::List { node.b, node.c }); },
        blot_parse_ast::tag_case_expr => {
            let inputs = self.engine.tree.extra.items[node.a..node.a + 2]; output += self.engine.tree.list(blot_parse_ast::List { inputs[0], inputs[1] });
            for arm in self.engine.tree.list(blot_parse_ast::List { node.b, node.c }) { let start = self.engine.tree.node(arm).c; let details = self.engine.tree.extra.items[start..start + 2]; if details[0] != 0 { output += details[0]; } output += details[1]; }
        },
        blot_parse_ast::tag_if_let_stmt => { output += node.b; for body in self.engine.tree.extra.items[node.c..node.c + 2] { if body != 0 { output += body; } } },
        blot_parse_ast::tag_for_stmt => { output += node.b; let end = self.engine.tree.extra.items[node.c]; if end != 0 { output += end; } output += self.engine.tree.extra.items[node.c + 1]; },
        blot_parse_ast::tag_range_stmt => { output += node.a; output += node.b; output += node.c; },
        blot_parse_ast::tag_forever_stmt => { output += node.a; },
        blot_parse_ast::tag_package_pack => { output += self.engine.tree.extra.items[node.c]; },
        blot_parse_ast::tag_package_unpack => { output += node.a; output += self.engine.tree.extra.items[node.c + 2]; },
        _ => {},
    }
}
fn lambda<E>(self: Walker<E>&, source: AstId, depth: i64) -> Error {
    let node = self.engine.tree.node(source); let ty = self.engine.types.node(self.engine.types.head(self.engine.expr_types[source], 0));
    if ty.tag == Tag.usage && ty.b == blot_parse_ast::usagekind_cleanup { if !blot_check_cleanup_contracts::source(self.engine, source) { let error = self.engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, source); if error != Error.none { return error; } } }
    if blot_check_cleanup_contracts::pureNominal(self.engine.types, self.engine.nominals, self.engine.expr_types[node.a]) { let error = self.engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, node.a); if error != Error.none { return error; } }
    let once = ty.tag == Tag.usage && ty.b == blot_parse_ast::usagekind_once; var captured: u32[>..] = []; let error = captures(self, node.b, source, once, captured, depth + 1); if error != Error.none { return error; }
    var previous: State[>..] = []; let error = snapshot(self, previous); if error != Error.none { return error; }
    for binding in captured { { let optional_binding_69 .= self.state(binding); if optional_binding_69 { let entry .= optional_binding_69; entry.first = 0;  } } }
    let outer_returns = self.returns; let outer_breaks = self.breaks; self.returns .= null; self.breaks .= null;
    var error = introduce(self, self.engine.resolved[node.a]); if error == Error.none { let flow, failure = expression(self, node.b, depth + 1); error = failure; }
    self.returns .= outer_returns; self.breaks .= outer_breaks; restore(self, previous); return error;
}
fn branches<E>(self: Walker<E>&, left: AstId, right: AstId, suites: bool, depth: i64) -> Outcome, Error {
    var prior: State[>..] = []; let error = snapshot(self, prior); if error != Error.none { return Outcome.live, error; }
    var left_flow = Outcome.live; var right_flow = Outcome.live;
    if suites { let flow, error = suite(self, left, depth + 1); if error != Error.none { return flow, error; } left_flow = flow; }
    else { let flow, error = expression(self, left, depth + 1); if error != Error.none { return flow, error; } left_flow = flow; }
    self.states.resize(prior.len); var after: State[>..] = []; let error = snapshot(self, after); if error != Error.none { return Outcome.live, error; } restore(self, prior);
    if right != 0 { if suites { let flow, error = suite(self, right, depth + 1); if error != Error.none { return flow, error; } right_flow = flow; } else { let flow, error = expression(self, right, depth + 1); if error != Error.none { return flow, error; } right_flow = flow; } }
    self.states.resize(prior.len); for &entry, index in self.states { let first = after[index]; if right_flow == Outcome.exit { entry = first; } else if left_flow != Outcome.exit && entry.first == 0 { entry.first = first.first; } }
    if left_flow == Outcome.exit && right_flow == Outcome.exit { return Outcome.exit, Error.none; } return Outcome.live, Error.none;
}
fn cases<E>(self: Walker<E>&, node: blot_parse_ast::Node, depth: i64) -> Outcome, Error {
    let inputs = self.engine.tree.extra.items[node.a..node.a + 2]; for input in self.engine.tree.list(blot_parse_ast::List { inputs[0], inputs[1] }) { let flow, error = expression(self, input, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } }
    var before: State[>..] = []; let error = snapshot(self, before); if error != Error.none { return Outcome.live, error; } var joined: State[>..] = []; let error = snapshot(self, joined); if error != Error.none { return Outcome.live, error; } var live = false;
    for arm_id in self.engine.tree.list(blot_parse_ast::List { node.b, node.c }) { restore(self, before); let arm = self.engine.tree.node(arm_id);
        for row in self.engine.tree.list(blot_parse_ast::List { arm.a, arm.b }) { for pattern_id in self.engine.tree.children(row) { let error = pattern(self, pattern_id, depth + 1); if error != Error.none { return Outcome.live, error; } } }
        let details = self.engine.tree.extra.items[arm.c..arm.c + 2];
        if details[0] != 0 { let flow, error = expression(self, details[0], depth + 1); if error != Error.none { return flow, error; } if flow == Outcome.exit { self.states.resize(before.len); continue; }
            for &entry, index in before { if entry.first == 0 { entry.first = self.states[index].first; } }
            for entry in self.states[before.len..] { if entry.first != 0 { let error = self.engine.usageDiagnostic(blot_check_check::Code.duplicate_owner, details[0]); if error != Error.none { return Outcome.live, error; } } }
        }
        let flow, error = expression(self, details[1], depth + 1); if error != Error.none { return flow, error; } self.states.resize(before.len);
        if flow == Outcome.live { live = true; for &entry, index in joined { if entry.first == 0 { entry.first = self.states[index].first; } } }
    } restore(self, joined); if !live { return Outcome.exit, Error.none; } return Outcome.live, Error.none;
}
fn admitsAffine<E>(self: Walker<E>&, callee_source: AstId) -> bool, Error {
    var task_head = callee_source;
    for depth in 0..128 { let candidate = self.engine.tree.node(task_head); if candidate.tag == blot_parse_ast::tag_apply || candidate.tag == blot_parse_ast::tag_group { task_head = candidate.a; continue; }
        if candidate.tag == blot_parse_ast::tag_intrinsic && blot_check_task_types::lookup(self.engine.pool.get(candidate.a)).present { return true, Error.none; } break;
    }
    var source = callee_source; if self.engine.isSpawnUse(source) { return true, Error.none; } while self.engine.tree.node(source).tag == blot_parse_ast::tag_group { source = self.engine.tree.node(source).a; }
    let node = self.engine.tree.node(source); if node.tag == blot_parse_ast::tag_lambda || node.tag == blot_parse_ast::tag_constructor_ref { return true, Error.none; }
    let binding = self.engine.resolved[source]; if binding == 0 { return false, Error.none; } let declaration = self.engine.bindings[binding];
    if declaration.capability_flow == blot_check_check::CapabilityFlow.consume_task || declaration.capability_flow == blot_check_check::CapabilityFlow.spawn_task { return true, Error.none; }
    if declaration.kind == blot_check_check::Kind.parameter { let parameter = self.engine.tree.parameter(declaration.declaration); var annotation = parameter.annotation; if annotation == 0 { return false, Error.none; }
        while self.engine.tree.node(annotation).tag == blot_parse_ast::tag_group || self.engine.tree.node(annotation).tag == blot_parse_ast::tag_type_usage || self.engine.tree.node(annotation).tag == blot_parse_ast::tag_type_forall {
            let wrapper = self.engine.tree.node(annotation); if wrapper.tag == blot_parse_ast::tag_group { annotation = wrapper.a; } else if wrapper.tag == blot_parse_ast::tag_type_forall { annotation = self.engine.tree.extra.items[wrapper.c]; } else { annotation = wrapper.b; }
        } let arrow = self.engine.tree.node(annotation); if arrow.tag != blot_parse_ast::tag_type_function { return false, Error.none; } var input = arrow.a; while self.engine.tree.node(input).tag == blot_parse_ast::tag_group { input = self.engine.tree.node(input).a; } return self.engine.tree.node(input).tag == blot_parse_ast::tag_type_usage, Error.none;
    }
    var header = self.engine.types.node(self.engine.types.head(declaration.ty, 0)); while header.tag == Tag.usage || header.tag == Tag.forall { header = self.engine.types.node(self.engine.types.head(header.a, 0)); }
    if header.tag != Tag.function { return false, Error.none; } if self.engine.types.node(header.a).tag == Tag.usage { return true, Error.none; } return affineNominal(self.engine.types, self.engine.nominals, header.a);
}
fn inspectRead<E>(self: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    var operand = source; while self.engine.tree.node(operand).tag == blot_parse_ast::tag_group { operand = self.engine.tree.node(operand).a; }
    if self.engine.tree.node(operand).tag == blot_parse_ast::tag_name { { let optional_binding_68 .= self.state(self.engine.resolved[operand]); if optional_binding_68 { let entry .= optional_binding_68;
        if entry.loan != 0 { let error = self.engine.usageDiagnostic(blot_check_check::Code.borrow_conflict, operand); if error != Error.none { return Outcome.live, error; } }
        if entry.first != 0 { let error = self.engine.usageDiagnostic(blot_check_check::Code.use_after_move, operand); if error != Error.none { return Outcome.live, error; } }
     } } return Outcome.live, Error.none; } return expression(self, source, depth + 1);
}
fn taskReadWrite<E>(self: Walker<E>&, source: AstId, depth: i64) -> bool, Outcome, Error {
    if !self.task_views || self.engine.tree.node(source).tag != blot_parse_ast::tag_apply { return false, Outcome.live, Error.none; }
    var head = source; var arguments: AstId[3]; var count: i64 = 0;
    while self.engine.tree.node(head).tag == blot_parse_ast::tag_apply && count < arguments.len { arguments[count] = self.engine.tree.node(head).b; count += 1; head = self.engine.tree.node(head).a; }
    if self.engine.tree.node(head).tag == blot_parse_ast::tag_intrinsic { let operation = blot_check_task_types::lookup(self.engine.pool.get(self.engine.tree.node(head).a));
        if operation.present && (operation.value == blot_check_task_types::Op.read || operation.value == blot_check_task_types::Op.write) && count == blot_check_task_types::arity(operation.value) {
            let flow, error = inspectRead(self, arguments[count - 1], depth); if error != Error.none || flow == Outcome.exit { return true, flow, error; }
            var index = count - 1; while index != 0 { index -= 1; let flow, error = expression(self, arguments[index], depth + 1); if error != Error.none || flow == Outcome.exit { return true, flow, error; } }
            return true, Outcome.live, Error.none;
        }
    } return false, Outcome.live, Error.none;
}
fn loanExpression<E>(self: Walker<E>&, source: AstId, depth: i64) -> bool, Outcome, Error {
    let node = self.engine.tree.node(source); if node.tag != blot_parse_ast::tag_apply { return false, Outcome.live, Error.none; }
    for &loan in self.engine.usage_loans { if loan.source != source { continue; }
        if loan.acquire != 0 {
            let flow, error = expression(self, loan.acquire, depth + 1); if error != Error.none { return true, flow, error; } let flow, error = expression(self, loan.release, depth + 1); if error != Error.none { return true, flow, error; }
            if loan.callback == 0 { return true, Outcome.live, Error.none; } if self.region_count == self.regions.len { return true, Outcome.live, Error.type_limit; }
            self.regions[self.region_count] = loan.region; self.region_count += 1; let flow, error = expression(self, loan.callback, depth + 1); self.region_count -= 1; return true, Outcome.live, error;
        }
        var first = node.a; while self.engine.tree.node(first).tag == blot_parse_ast::tag_group { first = self.engine.tree.node(first).a; } var owner = self.engine.tree.node(first).b; while self.engine.tree.node(owner).tag == blot_parse_ast::tag_group { owner = self.engine.tree.node(owner).a; }
        var binding: u32 = 0; if self.engine.tree.node(owner).tag == blot_parse_ast::tag_name { binding = self.engine.resolved[owner]; }
        { let optional_binding_67 .= self.state(binding); if optional_binding_67 { let entry .= optional_binding_67; if entry.first != 0 || entry.loan != 0 { let error = self.engine.usageDiagnostic(blot_check_check::Code.borrow_conflict, owner); if error != Error.none { return true, Outcome.live, error; } } entry.loan = source;  }
        else { let flow, error = expression(self, owner, depth + 1); if error != Error.none || flow == Outcome.exit { return true, flow, error; } } }
        var error = Error.none;
        if self.region_count == self.regions.len { error = Error.type_limit; }
        else { self.regions[self.region_count] = loan.region; self.region_count += 1; let flow, failure = expression(self, node.b, depth + 1); error = failure; self.region_count -= 1; }
        { let optional_binding_66 .= self.state(binding); if optional_binding_66 { let entry .= optional_binding_66; entry.loan = 0;  } } return true, Outcome.live, error;
    } return false, Outcome.live, Error.none;
}
recursive fn expression<E>(self: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    if source == 0 { return Outcome.live, Error.none; } let error = self.charge(depth); if error != Error.none { return Outcome.live, error; } let node = self.engine.tree.node(source);
    let handled, flow, error = taskReadWrite(self, source, depth); if handled || error != Error.none { return flow, error; }
    let handled, flow, error = loanExpression(self, source, depth); if handled || error != Error.none { return flow, error; }
    match node.tag {
        blot_parse_ast::tag_name, blot_parse_ast::tag_task_region => { let error = use(self, self.engine.resolved[source], source); if error != Error.none { return Outcome.live, error; } },
        blot_parse_ast::tag_lambda => { let error = lambda(self, source, depth + 1); if error != Error.none { return Outcome.live, error; } },
        blot_parse_ast::tag_group, blot_parse_ast::tag_field_access, blot_parse_ast::tag_type_witness => { return expression(self, node.a, depth + 1); },
        blot_parse_ast::tag_return_stmt => { let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } { let optional_binding_65 .= self.returns; if optional_binding_65 { let frame .= optional_binding_65; record(self, frame);  } } return Outcome.exit, Error.none; },
        blot_parse_ast::tag_function_return_stmt => { let flow, error = expression(self, node.a, depth + 1); if error != Error.none { return flow, error; } return Outcome.exit, Error.none; },
        blot_parse_ast::tag_break_stmt, blot_parse_ast::tag_continue_stmt => { { let optional_binding_64 .= self.breaks; if optional_binding_64 { let frame .= optional_binding_64; record(self, frame);  } } return Outcome.exit, Error.none; },
        blot_parse_ast::tag_yield_stmt => { let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } },
        blot_parse_ast::tag_field, blot_parse_ast::tag_unary, blot_parse_ast::tag_operator_tail => { if node.b != 0 { let flow, error = expression(self, node.b, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } } },
        blot_parse_ast::tag_binary => { let flow, error = expression(self, node.b, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } let flow, error = expression(self, node.c, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } },
        blot_parse_ast::tag_apply, blot_parse_ast::tag_index_access => { return application(self, source, depth); },
        blot_parse_ast::tag_case_expr => { return cases(self, node, depth + 1); },
        blot_parse_ast::tag_infix_chain => { let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } for tail in self.engine.tree.list(blot_parse_ast::List { node.b, node.c }) { let flow, error = expression(self, tail, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } } },
        blot_parse_ast::tag_if_let_stmt => {
            let flow, error = expression(self, node.b, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } let before = self.states.len;
            let error = pattern(self, node.a, depth + 1); if error != Error.none { return Outcome.live, error; } let bodies = self.engine.tree.extra.items[node.c..node.c + 2];
            let result, error = branches(self, bodies[0], bodies[1], true, depth + 1); self.states.resize(before); return result, error;
        },
        blot_parse_ast::tag_request_case => {
            var prior: State[>..] = []; let error = snapshot(self, prior); if error != Error.none { return Outcome.live, error; }
            for arm_id in self.engine.tree.list(blot_parse_ast::List { node.b, node.c }) { restore(self, prior); let arm = self.engine.tree.node(arm_id); if arm.b != 0 { let error = pattern(self, arm.b, depth + 1); if error != Error.none { return Outcome.live, error; } }
                let flow, error = suite(self, arm.c, depth + 1); if error != Error.none { return flow, error; } self.states.resize(prior.len);
                for after, index in self.states { let before = prior[index]; if after.first != before.first || after.loan != before.loan { let error = self.engine.usageDiagnostic(blot_check_check::Code.multiplicity_unknown, arm_id); if error != Error.none { return Outcome.live, error; } } }
            } restore(self, prior);
        },
        blot_parse_ast::tag_if_expr, blot_parse_ast::tag_if_stmt => { let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } return branches(self, node.b, node.c, node.tag == blot_parse_ast::tag_if_stmt, depth + 1); },
        blot_parse_ast::tag_let_stmt => {
            let binding = self.engine.tree.binding(source); let target = self.engine.resolved[binding.pattern];
            if target != 0 && blot_check_cleanup_contracts::pureNominal(self.engine.types, self.engine.nominals, self.engine.bindings[target].ty) && !blot_check_cleanup_contracts::source(self.engine, binding.value) { let error = self.engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, binding.value); if error != Error.none { return Outcome.live, error; } }
            let flow, error = expression(self, binding.value, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; }
            if binding.fallback != 0 { var prior: State[>..] = []; let error = snapshot(self, prior); if error != Error.none { return Outcome.live, error; } let flow, error = suite(self, binding.fallback, depth + 1); restore(self, prior); if error != Error.none { return flow, error; } }
            let error = pattern(self, binding.pattern, depth + 1); if error != Error.none { return Outcome.live, error; }
        },
        blot_parse_ast::tag_use_stmt, blot_parse_ast::tag_iterator_bind, blot_parse_ast::tag_rebind_stmt => {
            let flow, error = expression(self, node.b, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } let error = introduce(self, self.engine.resolved[source]); if error != Error.none { return Outcome.live, error; }
        },
        blot_parse_ast::tag_block => { if node.c != 0 && self.states.len != 0 { let error = self.engine.usageDiagnostic(blot_check_check::Code.multiplicity_unknown, source); if error != Error.none { return Outcome.live, error; } } return block(self, source, depth + 1); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_array, blot_parse_ast::tag_record => { for child in self.engine.tree.children(source) { let flow, error = expression(self, child, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } } },
        blot_parse_ast::tag_for_stmt, blot_parse_ast::tag_range_stmt, blot_parse_ast::tag_forever_stmt => { return loopExpression(self, source, depth); },
        blot_parse_ast::tag_package_pack => { let flow, error = expression(self, self.engine.tree.extra.items[node.c], depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } },
        blot_parse_ast::tag_package_unpack => { let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } let error = introduce(self, self.engine.resolved[source]); if error != Error.none { return Outcome.live, error; } return expression(self, self.engine.tree.extra.items[node.c + 2], depth + 1); },
        _ => {},
    } return Outcome.live, Error.none;
}
fn application<E>(self: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    let node = self.engine.tree.node(source); var callee_source = node.a; while self.engine.tree.node(callee_source).tag == blot_parse_ast::tag_group { callee_source = self.engine.tree.node(callee_source).a; } let callee_node = self.engine.tree.node(callee_source);
    if node.tag == blot_parse_ast::tag_apply && callee_node.tag == blot_parse_ast::tag_intrinsic {
        let name = self.engine.pool.get(callee_node.a);
        if name == "@usage.share" || name == "@resource.release" { return expression(self, node.b, depth + 1); }
        if name == "@usage.read" || name == "@usage.length" { return inspectRead(self, node.b, depth); }
    }
    if node.tag == blot_parse_ast::tag_apply { for index in 0..self.region_count { let footprint, error = self.engine.usageLoanFootprint(node.b, self.regions[index]); if error != Error.none { return Outcome.live, error; }
        if footprint { let admits, error = admitsAffine(self, node.a); if error != Error.none { return Outcome.live, error; } if !admits { let error = self.engine.usageDiagnostic(blot_check_check::Code.borrow_escape, node.b); if error != Error.none { return Outcome.live, error; } } }
    } }
    let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } let flow, error = expression(self, node.b, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; }
    if node.tag == blot_parse_ast::tag_apply {
        let affine, error = affineNominal(self.engine.types, self.engine.nominals, self.engine.expr_types[node.b]); if error != Error.none { return Outcome.live, error; } var borrowed_value = false;
        if !affine { let value, error = borrowed(self.engine.types, self.engine.expr_types[node.b]); if error != Error.none { return Outcome.live, error; } borrowed_value = value; }
        if affine || borrowed_value { var callee = self.engine.types.node(self.engine.types.head(self.engine.expr_types[node.a], 0)); if callee.tag == Tag.usage { callee = self.engine.types.node(self.engine.types.head(callee.a, 0)); }
            var admits = false; if callee.tag == Tag.function { let value, error = admitsAffine(self, node.a); if error != Error.none { return Outcome.live, error; } admits = value; }
            if !admits { let error = self.engine.usageDiagnostic(blot_check_check::Code.multiplicity_unknown, source); if error != Error.none { return Outcome.live, error; } }
        }
    } return Outcome.live, Error.none;
}
fn loopExpression<E>(self: Walker<E>&, source: AstId, depth: i64) -> Outcome, Error {
    let node = self.engine.tree.node(source);
    if node.tag == blot_parse_ast::tag_range_stmt { let flow, error = expression(self, node.a, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } }
    if node.tag != blot_parse_ast::tag_forever_stmt { let flow, error = expression(self, node.b, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } }
    if node.tag == blot_parse_ast::tag_for_stmt { let end = self.engine.tree.extra.items[node.c]; if end != 0 { let flow, error = expression(self, end, depth + 1); if error != Error.none || flow == Outcome.exit { return flow, error; } } }
    var single = false; if node.tag == blot_parse_ast::tag_range_stmt { single = singleIteration(self, node.a, node.b); } if node.tag == blot_parse_ast::tag_for_stmt { single = singleIteration(self, node.b, self.engine.tree.extra.items[node.c]); }
    var prior: State[>..] = []; let error = snapshot(self, prior); if error != Error.none { return Outcome.live, error; } var exits: State[>..] = []; let error = snapshot(self, exits); if error != Error.none { return Outcome.live, error; }
    var frame = ExitFrame { exits }; let outer = self.breaks; self.breaks .= frame; let flow, error = loopBody(self, source, node, prior, frame, single, depth); self.breaks .= outer; if error != Error.none { return flow, error; } restore(self, exits);
    if (node.tag == blot_parse_ast::tag_forever_stmt || single) && !frame.seen { return Outcome.exit, Error.none; } return Outcome.live, Error.none;
}
fn loopBody<E>(self: Walker<E>&, source: AstId, node: blot_parse_ast::Node, prior: const State[:], frame: ExitFrame&, single: bool, depth: i64) -> Outcome, Error {
    if node.tag == blot_parse_ast::tag_for_stmt { let error = pattern(self, node.a, depth + 1); if error != Error.none { return Outcome.live, error; } }
    var body = node.a; if node.tag == blot_parse_ast::tag_range_stmt { body = node.c; } if node.tag == blot_parse_ast::tag_for_stmt { body = self.engine.tree.extra.items[node.c + 1]; }
    let flow, error = suite(self, body, depth + 1); if error != Error.none { return flow, error; } self.states.resize(prior.len);
    if flow == Outcome.live && !single { for entry, index in self.states { if entry.first != prior[index].first { let error = self.engine.usageDiagnostic(blot_check_check::Code.once_reused, source); if error != Error.none { return flow, error; } break; } } }
    if flow == Outcome.live && single { record(self, frame); } return flow, Error.none;
}
fn validate<E>(engine: E) -> Error {
    var states: State[>..<] = []; var walker = Walker<E> { engine, states: states, task_views: engine.pool.lookup("@task.read").present || engine.pool.lookup("@task.write").present };
    for root in engine.tree.roots.items { if engine.tree.node(root).tag != blot_parse_ast::tag_value_decl { continue; } walker.states.clear(); walker.remaining = 65536; let binding = engine.resolved[root]; let body = engine.tree.value_decl(root).body;
        if binding != 0 && blot_check_cleanup_contracts::pureNominal(engine.types, engine.nominals, engine.bindings[binding].ty) && !blot_check_cleanup_contracts::source(engine, body) { let error = engine.usageDiagnostic(blot_check_check::Code.cleanup_not_safe, body); if error != Error.none { return error; } }
        let flow, error = expression(walker, body, 0); if error == Error.type_limit { let error = engine.usageDiagnostic(blot_check_check::Code.usage_analysis_limit, root); if error != Error.none { return error; } continue; } if error != Error.none { return error; }
    } return Error.none;
}

fn outcomeCode(value: Outcome) -> u32 {
    match value {
        Outcome.live => { return 0; },
        Outcome.exit => { return 1; },
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
        Mode.affine => { return 0; },
        Mode.any => { return 1; },
        Mode.borrow => { return 2; },
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





import support.pooled_buffer;
import support.pooled_map;
import dictionary;
struct PooledMemo {safe:blot_support_pooled_map::Map<Id,bool> = blot_support_pooled_map::Map<Id,bool>{},epoch:blot_support::Option<u64> = blot_support::none<u64>(),row_epoch:blot_support::Option<u64> = blot_support::none<u64>(),nominals:blot_support_pooled_buffer::Buffer<NominalFact> = blot_support_pooled_buffer::Buffer<NominalFact>{}}
reusable[] var pooled_safe_slots:dictionary_slot<Id,bool>[>..];
reusable[] var pooled_nominal_facts:NominalFact[>..];
fn deinit(self:PooledMemo&) {blot_support_pooled_map::deinit(self.safe,pooled_safe_slots);blot_support_pooled_buffer::deinit(self.nominals,pooled_nominal_facts);}
fn containsNominalMemoWork(store: const blot_check_types::Store&, nominals, root: Id, work: Work&, memo: PooledMemo&) -> bool, Error {
    let epoch = store.mutation_epoch; var same_catalog = memo.nominals.items.len == nominals.len;
    if same_catalog { for prior, index in memo.nominals.items { let error = work.charge(1); if error != Error.none { return false, error; } let nominal = nominals[index]; if prior.identity != nominal.identity || prior.has_usage != nominal.has_usage { same_catalog = false; break; } } }
    if !memo.epoch.present || memo.epoch.value != epoch || !memo.row_epoch.present || memo.row_epoch.value != store.effects.mutation_epoch || !same_catalog || epoch == 0xffffffffffffffff { memo.safe.clear(); }
    memo.epoch = blot_support::some(epoch); memo.row_epoch = blot_support::some(store.effects.mutation_epoch);
    if !same_catalog { memo.nominals.clear(); for nominal in nominals { let error = work.charge(1); if error != Error.none { return false, error; } let append_error=blot_support_pooled_buffer::push(memo.nominals,NominalFact { nominal.identity, nominal.has_usage },pooled_nominal_facts); if append_error!=Error.none {return false,append_error;} } }
    let context = NominalStore { store, nominals, work }; if epoch == 0xffffffffffffffff || store.effects.mutation_epoch == 0xffffffffffffffff { return inspectWithPooledMemo(context, root, Mode.any, work, null); } return inspectWithPooledMemo(context, root, Mode.any, work, memo);
}
fn addPooled(self: Pending&, source, raw: Id, budget: Work&, known: PooledMemo?) -> Error {
    if !source.valid(raw) { return Error.type_limit; } let id = source.head(raw, 0); if !source.valid(id) { return Error.type_limit; }
    { let optional_binding_72 .= known; if optional_binding_72 { let cache .= optional_binding_72; let error = budget.charge(1); if error != Error.none { return error; } if cache.safe.contains(id) { return Error.none; }  } }
    var slot = ((id as u64 *% 0x9e3779b1) & (self.slots.len as u64 - 1)) as i64;
    while true { let error = budget.charge(1); if error != Error.none { return error; } let prior = self.slots[slot]; if prior == 0 { break; } if self.ids[prior - 1] == id { return Error.none; } slot = (slot + 1) & (self.slots.len - 1); }
    if self.count == self.ids.len { return Error.type_limit; } self.ids[self.count] = id; self.count += 1; self.slots[slot] = self.count as u16; return Error.none;
}
fn inspectWithPooledMemo(store, root: Id, mode: Mode, work: Work&, memo: PooledMemo?) -> bool, Error {
    var pending = Pending {}; let error = pending.addPooled(store, root, work, memo); if error != Error.none { return false, error; } var next: i64 = 0;
    while next != pending.count { let error = work.charge(1); if error != Error.none { return false, error; } let id = pending.ids[next]; next += 1; let node = store.node(id);
        let error = store.shape(node); if error != Error.none { return false, error; }
        if mode != Mode.borrow && node.tag == Tag.nominal { let property, error = store.nominalProperty(node, mode); if error != Error.none { return false, error; } if property { return true, Error.none; } }
        if mode == Mode.any && (node.tag == Tag.scoped || node.tag == Tag.instance_version) { return true, Error.none; }
        if node.tag == Tag.usage { if mode == Mode.any { return true, Error.none; } let kind = node.b;
            if mode == Mode.borrow { if kind == blot_parse_ast::usagekind_borrow || kind == blot_parse_ast::usagekind_borrow_mut { return true, Error.none; } }
            else if kind == blot_parse_ast::usagekind_unique || kind == blot_parse_ast::usagekind_borrow_mut || kind == blot_parse_ast::usagekind_once { return true, Error.none; }
        }
        var child: Id[1] = [node.a]; var edges: const Id[:] = [];
        match node.tag {
            Tag.usage, Tag.array, Tag.list, Tag.cursor, Tag.forall, Tag.existential => { edges = child; },
            Tag.product => { edges = store.list(blot_check_types::List { node.a, node.b }); },
            Tag.nominal, Tag.projection => { edges = store.nominalArguments(node); },
            Tag.function => { if mode == Mode.any { let error = pending.addPooled(store, node.a, work, memo); if error != Error.none { return false, error; } let error = pending.addPooled(store, node.b, work, memo); if error != Error.none { return false, error; } } },
            Tag.record => { for index in 0..node.b { let error = work.charge(1); if error != Error.none { return false, error; } let error = pending.addPooled(store, store.recordField(node, index).ty, work, memo); if error != Error.none { return false, error; } } },
            _ => {},
        }
        let error = work.charge(edges.len); if error != Error.none { return false, error; } for edge in edges { let error = pending.addPooled(store, edge, work, memo); if error != Error.none { return false, error; } }
    }
    { let optional_binding_71 .= memo; if optional_binding_71 { let cache .= optional_binding_71; for index in 0..pending.count { let error = work.charge(1); if error != Error.none { return false, error; } blot_support_pooled_map::insert(cache.safe,pending.ids[index],true,pooled_safe_slots); }  } } return false, Error.none;
}
