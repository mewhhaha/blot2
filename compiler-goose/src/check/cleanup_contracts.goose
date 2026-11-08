// Cleanup authority comes from a finite executable recipe at each boundary.
namespace blot_check_cleanup_contracts;
import reuse.principal_interface;

import check.check_packet_owner;
import check.closed_nominal_storage;
import check.core;
import check.effects;
import check.rank_equal;
import check.types;
import check.usage_check;
import parse.ast;
import support.error;

type Error = blot_error::Error;
type Id = blot_check_types::Id;
type Tag = blot_check_types::Tag;
struct Budget { remaining: i64 = 65536 }
fn repeat(self_: Budget&, before: i64, iterations: u32) -> Error { let work = before - self_.remaining; if iterations <= 1 || work == 0 { return blot_error::Error.none; } let repeats = iterations - 1; if repeats > self_.remaining / work { return blot_error::Error.unsafe_cleanup; } self_.remaining -= work * repeats; return blot_error::Error.none; }
fn charge(self_: Budget&, depth: i64) -> Error { if depth >= 128 || self_.remaining == 0 { return blot_error::Error.unsafe_cleanup; } self_.remaining -= 1; return blot_error::Error.none; }
fn scalar(tag: Tag) -> bool { return tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32; }
fn typeBound(store, id: Id) -> bool { return id < store.nodes.len; }
fn rowBound(store, id: u32) -> bool { return id < store.effects.rows.len; }
struct NominalTypes<S,N> { store: S, nominals: N }
fn head<S,N>(self_: const NominalTypes<S,N>&, id: Id, cursor: u32) -> Id { return self_.store.head(id, cursor); }
fn node<S,N>(self_: const NominalTypes<S,N>&, id: Id) -> blot_check_types::Node { return self_.store.node(id); }
fn row<S,N>(self_: const NominalTypes<S,N>&, id: u32) -> blot_check_effects::Row { return self_.store.row(id); }
fn rowLabels<S,N>(self_: const NominalTypes<S,N>&, id: u32) -> const u32[:] { return self_.store.rowLabels(id); }
fn operation<S,N>(self_: const NominalTypes<S,N>&, id: u32) -> blot_check_types::Operation { return self_.store.operation(id); }
fn list<S,N>(self_: const NominalTypes<S,N>&, values: blot_check_types::List) -> const Id[:] { return self_.store.list(values); }
fn nominalArguments<S,N>(self_: const NominalTypes<S,N>&, value: blot_check_types::Node) -> const Id[:] { return self_.store.nominalArguments(value); }
fn recordField<S,N>(self_: const NominalTypes<S,N>&, value: blot_check_types::Node, index: i64) -> blot_check_types::Field { return self_.store.recordField(value, index); }
fn typeBound<S,N>(self_: const NominalTypes<S,N>&, id: Id) -> bool { return id < self_.store.nodes.len; }
fn rowBound<S,N>(self_: const NominalTypes<S,N>&, id: u32) -> bool { return id < self_.store.effects.rows.len; }
fn payload(store, id: Id) -> bool { let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); return payloadNominal(store, empty, id); }
fn extraWords(store:const blot_check_types::Store&)->const u32[:] {return store.extra.items;}
fn extraWords(store:const blot_check_core::Types&)->const u32[:] {return store.extra;}
fn payloadNominal(store, nominals, id: Id) -> bool { var budget = Budget {..}; return payloadDepth(store, nominals, id, budget, 0); }
recursive fn payloadDepth<S,N>(store:S, nominals:const N[:], id: Id, budget: Budget&, depth: i64) -> bool {
    if budget.charge(depth) != blot_error::Error.none || !typeBound(store, id) { return false; } let node = store.node(store.head(id, 0));
    if scalar(node.tag) { return node.a == 0 && node.b == 0 && node.c == 0; }
    if node.tag == blot_check_types::Tag.array || node.tag == blot_check_types::Tag.list { return node.b == 0 && node.c == 0 && payloadDepth(store, nominals, node.a, budget, depth + 1); }
    let values = extraWords(store);
    if node.tag == blot_check_types::Tag.nominal {
        if node.c >= values.len || values[node.c] > values.len - node.c - 1 { return false; }
        for nominal in nominals { if budget.charge(depth) != blot_error::Error.none { return false; } if nominal.identity.unit != node.a || nominal.identity.decl != node.b { continue; }
            if !nominal.closed_storage || nominal.has_usage || values[node.c] != nominal.parameters.len { return false; } for argument in store.nominalArguments(node) { if !payloadDepth(store, nominals, argument, budget, depth + 1) { return false; } } return true;
        } return false;
    }
    if (node.tag != blot_check_types::Tag.product && node.tag != blot_check_types::Tag.record) || node.c != 0 { return false; } var stride: i64 = 1; var first = node.a as i64; if node.tag == blot_check_types::Tag.record { stride = 2; first += 1; }
    if node.a > values.len || node.b > (values.len - node.a) / stride { return false; } for index in 0..node.b { if !payloadDepth(store, nominals, values[first + index * stride], budget, depth + 1) { return false; } } return true;
}
recursive fn equalStorage(store: const blot_check_core::Types&, left: Id, right: Id, budget: Budget&, depth: i64) -> bool, Error {
    let error = budget.charge(depth); if error != blot_error::Error.none { return false, error; } if !typeBound(store, left) || !typeBound(store, right) { return false, blot_error::Error.unsafe_cleanup; } if left == right { return true, blot_error::Error.none; }
    let a = store.node(left); let b = store.node(right); if a.tag != b.tag { return false, blot_error::Error.none; } if scalar(a.tag) { return true, blot_error::Error.none; }
    if a.tag == blot_check_types::Tag.array || a.tag == blot_check_types::Tag.list { return equalStorage(store, a.a, b.a, budget, depth + 1); }
    if a.tag == blot_check_types::Tag.nominal { if a.a != b.a || a.b != b.b { return false, blot_error::Error.none; } let aa = store.nominalArguments(a); let bb = store.nominalArguments(b); if aa.len != bb.len { return false, blot_error::Error.none; }
        for av, index in aa { let equal, error = equalStorage(store, av, bb[index], budget, depth + 1); if error != blot_error::Error.none || !equal { return equal, error; } } return true, blot_error::Error.none;
    }
    if (a.tag != blot_check_types::Tag.product && a.tag != blot_check_types::Tag.record) || a.b != b.b { return false, blot_error::Error.none; }
    for index in 0..a.b {
        if a.tag == blot_check_types::Tag.record { let af = store.recordField(a, index); var found = false;
            for other in 0..b.b { let error = budget.charge(depth); if error != blot_error::Error.none { return false, error; } let bf = store.recordField(b, other); if af.name != bf.name { continue; } if found { return false, blot_error::Error.none; } let equal, error = equalStorage(store, af.ty, bf.ty, budget, depth + 1); if error != blot_error::Error.none || !equal { return equal, error; } found = true; } if !found { return false, blot_error::Error.none; }
        } else { let equal, error = equalStorage(store, store.extra[a.a + index], store.extra[b.a + index], budget, depth + 1); if error != blot_error::Error.none || !equal { return equal, error; } }
    } return true, blot_error::Error.none;
}
fn closedStorage(module: const blot_check_core::Module&) -> Error {
    var budget = Budget {..}; var constructor_work = blot_check_usage_check::Work {..};
    for node in module.nodes { let error = budget.charge(0); if error != blot_error::Error.none { return error; }
        if node.tag != blot_check_core::Tag.product && node.tag != blot_check_core::Tag.record && node.tag != blot_check_core::Tag.array && node.tag != blot_check_core::Tag.construct { continue; }
        var ty = node.ty; if !typeBound(module.types, ty) { return blot_error::Error.unsafe_cleanup; } let wrapper = module.types.node(ty);
        if wrapper.tag == blot_check_types::Tag.usage { if wrapper.c != 0 || (wrapper.b != blot_parse_ast::usagekind_unique && wrapper.b != blot_parse_ast::usagekind_shared) { return blot_error::Error.unsafe_cleanup; } ty = wrapper.a; }
        if !payloadDepth(module.types, module.nominals, ty, budget, 0) { if wrapper.tag == blot_check_types::Tag.usage { return blot_error::Error.unsafe_cleanup; } continue; }
        if node.tag == blot_check_core::Tag.construct { let valid, error = blot_check_closed_nominal_storage::construction(module, node, constructor_work); if error != blot_error::Error.none || !valid { return blot_error::Error.unsafe_cleanup; } continue; }
        let shape = module.types.node(ty); if node.op != blot_check_core::Op.none || node.a > module.extra.len || node.b > module.extra.len - node.a { return blot_error::Error.unsafe_cleanup; }
        if node.tag == blot_check_core::Tag.array { if (shape.tag != blot_check_types::Tag.array && shape.tag != blot_check_types::Tag.list) || node.c != 0 { return blot_error::Error.unsafe_cleanup; } }
        else { var expected = blot_check_types::Tag.record; if node.tag == blot_check_core::Tag.product { expected = blot_check_types::Tag.product; } if shape.tag != expected || shape.b != node.b { return blot_error::Error.unsafe_cleanup; } }
        if node.tag == blot_check_core::Tag.record && (node.c > module.extra.len || node.b > module.extra.len - node.c) { return blot_error::Error.unsafe_cleanup; } if node.tag == blot_check_core::Tag.product && node.c != 0 { return blot_error::Error.unsafe_cleanup; }
        for child, index in module.extra[node.a..node.a + node.b] { let error = budget.charge(0); if error != blot_error::Error.none { return error; } if child == 0 || child >= module.nodes.len { return blot_error::Error.unsafe_cleanup; } var expected = shape.a;
            if node.tag == blot_check_core::Tag.record { let slot = module.extra[node.c + index]; if slot >= node.b { return blot_error::Error.unsafe_cleanup; } for prior in module.extra[node.c..node.c + index] { let error = budget.charge(0); if error != blot_error::Error.none { return error; } if prior == slot { return blot_error::Error.unsafe_cleanup; } } expected = module.types.recordField(shape, slot).ty; }
            else if node.tag == blot_check_core::Tag.product { expected = module.types.extra[shape.a + index]; }
            let actual = module.typeOf(child); if !payloadDepth(module.types, module.nominals, actual, budget, 0) { return blot_error::Error.unsafe_cleanup; } let equal, error = equalStorage(module.types, expected, actual, budget, 0); if error != blot_error::Error.none || !equal { return blot_error::Error.unsafe_cleanup; }
        }
    } return blot_error::Error.none;
}
fn pureType(store, id: Id) -> bool { let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); return pureNominal(store, empty, id); }
fn pureNominal(store, nominals, id: Id) -> bool {
    if !typeBound(store, id) { return false; } let wrapper = store.node(store.head(id, 0)); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_cleanup || wrapper.c != 0 || !typeBound(store, wrapper.a) { return false; }
    let arrow = store.node(store.head(wrapper.a, 0)); if arrow.tag != blot_check_types::Tag.function || arrow.b != blot_check_types::unit || arrow.c != 0 || !rowBound(store, 0) || store.row(0).labels.len != 0 || store.row(0).tail != blot_check_effects::Tail.closed || !typeBound(store, arrow.a) { return false; }
    let owner = store.node(store.head(arrow.a, 0)); return owner.tag == blot_check_types::Tag.usage && owner.b == blot_parse_ast::usagekind_unique && owner.c == 0 && payloadNominal(store, nominals, owner.a);
}
fn hostType(store, id: Id) -> bool { let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); return hostNominal(store, empty, id); }
fn hostNominal(store, nominals, id: Id) -> bool {
    if !typeBound(store, id) { return false; } let wrapper = store.node(store.head(id, 0)); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_cleanup || wrapper.c != 0 || !typeBound(store, wrapper.a) { return false; }
    let arrow = store.node(store.head(wrapper.a, 0)); if arrow.tag != blot_check_types::Tag.function || arrow.b != blot_check_types::unit || !typeBound(store, arrow.a) || !rowBound(store, arrow.c) || store.row(arrow.c).tail != blot_check_effects::Tail.closed { return false; }
    let owner = store.node(store.head(arrow.a, 0)); if owner.tag != blot_check_types::Tag.usage || owner.b != blot_parse_ast::usagekind_unique || owner.c != 0 || !payloadNominal(store, nominals, owner.a) { return false; }
    let row = store.row(arrow.c); if row.labels.len != 1 || row.labels.start >= store.effects.labels.len { return false; } let labels = store.rowLabels(arrow.c); if labels[0] >= store.operations.len { return false; } let operation = store.operation(labels[0]);
    return operation.identity.unit == 0 && operation.identity.decl == 1 && operation.instance.unit == 0 && operation.instance.decl == 0 && operation.arguments.len == 0;
}
fn transferableType(store, id: Id) -> bool { let empty: const blot_check_core::Nominal[:] = default<const blot_check_core::Nominal[:]>(); return transferableNominal(store, empty, id); }
fn transferableNominal(store, nominals, id: Id) -> bool { let wrapper = store.node(store.head(id, 0)); if wrapper.tag != blot_check_types::Tag.usage { return payloadNominal(store, nominals, id); } if wrapper.c != 0 || (wrapper.b != blot_parse_ast::usagekind_unique && wrapper.b != blot_parse_ast::usagekind_shared) { return false; } return payloadNominal(store, nominals, wrapper.a); }
fn sourceHost(engine, root: blot_parse_ast::Id) -> bool {
    var id = root; var remaining: i64 = 128; while engine.tree.node(id).tag == blot_parse_ast::tag_group { if remaining == 0 { return false; } remaining -= 1; id = engine.tree.node(id).a; }
    if engine.tree.node(id).tag != blot_parse_ast::tag_name || engine.access_paths[id].len != 0 || engine.operation_refs[id] != 0 { return false; } let binding = engine.resolved[id];
    return binding != 0 && binding < engine.bindings.len && engine.bindings[binding].kind == blot_reuse_principal_interface::Kind.parameter && hostNominal(engine.types, engine.nominals, engine.bindings[binding].ty) && hostNominal(engine.types, engine.nominals, engine.expr_types[id]);
}
fn immutableHost(module: const blot_check_core::Module&, root: blot_check_core::Id) -> bool {
    if root == 0 || root >= module.nodes.len { return false; } let node = module.node(root);
    if node.tag != blot_check_core::Tag.reference || node.op != blot_check_core::Op.none || node.a >= module.references.len || node.b != 0 || node.c != 0 || node.ty >= module.types.nodes.len { return false; } let reference = module.reference(root);
    if (reference.unit != 0 && reference.unit != module.unit) || reference.binding == 0 || reference.binding >= module.bindings.len { return false; } let binding = module.bindings[reference.binding]; if binding.kind != blot_reuse_principal_interface::Kind.parameter || binding.ty >= module.types.nodes.len { return false; }
    if !hostNominal(module.types, module.nominals, binding.ty) { return false; } let equal, error = blot_check_rank_equal::equal(module.types, node.ty, binding.ty, true); return error == blot_error::Error.none && equal;
}
fn pureIntrinsic(name: const u8[:]) -> bool { return name.starts_with("@u32.") || name.starts_with("@f32.") || name == "@panic" || name == "@usage.read" || name == "@usage.length"; }
struct SourceReceipt { safe: bool = false, host: bool = false }
fn source(engine, root: blot_parse_ast::Id) -> bool { return sourceRecipe(engine, root, false).safe; }
fn sourceTransferred(engine, root: blot_parse_ast::Id) -> bool { return sourceRecipe(engine, root, true).safe; }
fn sourceForeign(engine, root: blot_parse_ast::Id) -> bool { return sourceRecipe(engine, root, false).host; }
struct SourceWalker<E> { engine: E, budget: Budget = Budget {..}, transferred: bool, host: bool = false }
recursive fn callable<E>(self_: SourceWalker<E>&, root: blot_parse_ast::Id, depth: i64) -> Error {
    let error = self_.budget.charge(depth); if error != blot_error::Error.none { return error; } let node = self_.engine.tree.node(root);
    match node.tag {
        blot_parse_ast::tag_group => { return callable(self_, node.a, depth + 1); },
        blot_parse_ast::tag_name => { if !sourceHost(self_.engine, root) { return blot_error::Error.unsafe_cleanup; } self_.host = true; },
        blot_parse_ast::tag_intrinsic => { if !pureIntrinsic(self_.engine.pool.get(node.a)) { return blot_error::Error.unsafe_cleanup; } },
        blot_parse_ast::tag_apply => { let error = callable(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.b, depth + 1); },
        _ => { return blot_error::Error.unsafe_cleanup; },
    } return blot_error::Error.none;
}
recursive fn integer<E>(self_: SourceWalker<E>&, root: blot_parse_ast::Id, depth: i64) -> u32, Error {
    let error = self_.budget.charge(depth); if error != blot_error::Error.none { return 0, error; } let node = self_.engine.tree.node(root); if node.tag == blot_parse_ast::tag_group { return integer(self_, node.a, depth + 1); } if node.tag != blot_parse_ast::tag_integer { return 0, blot_error::Error.unsafe_cleanup; } return node.a, blot_error::Error.none;
}
fn range<E>(self_: SourceWalker<E>&, first: blot_parse_ast::Id, end: blot_parse_ast::Id, body: blot_parse_ast::Id, depth: i64) -> Error {
    let low, error = integer(self_, first, depth + 1); if error != blot_error::Error.none { return error; } let high, error = integer(self_, end, depth + 1); if error != blot_error::Error.none { return error; } var iterations: u32 = 0; if low < high { iterations = high - low; }
    let before = self_.budget.remaining; let error = self_.budget.charge(depth + 1); if error != blot_error::Error.none { return error; } let error = expression(self_, body, depth + 1); if error != blot_error::Error.none { return error; } return self_.budget.repeat(before, iterations);
}
recursive fn expression<E>(self_: SourceWalker<E>&, id: blot_parse_ast::Id, depth: i64) -> Error {
    if id == 0 { return blot_error::Error.none; } let error = self_.budget.charge(depth); if error != blot_error::Error.none { return error; } let node = self_.engine.tree.node(id);
    match node.tag {
        blot_parse_ast::tag_name => {
            if self_.engine.access_paths[id].len != 0 || self_.engine.operation_refs[id] != 0 { return blot_error::Error.unsafe_cleanup; }
            if self_.transferred { let binding = self_.engine.resolved[id]; if binding == 0 || binding >= self_.engine.bindings.len || (!sourceHost(self_.engine, id) && (!transferableNominal(self_.engine.types, self_.engine.nominals, self_.engine.expr_types[id]) || !transferableNominal(self_.engine.types, self_.engine.nominals, self_.engine.bindings[binding].ty))) { return blot_error::Error.unsafe_cleanup; } }
        },
        blot_parse_ast::tag_integer, blot_parse_ast::tag_float, blot_parse_ast::tag_boolean, blot_parse_ast::tag_unit, blot_parse_ast::tag_string => {},
        blot_parse_ast::tag_apply => { let error = callable(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.b, depth + 1); },
        blot_parse_ast::tag_group, blot_parse_ast::tag_return_stmt, blot_parse_ast::tag_function_return_stmt => { return expression(self_, node.a, depth + 1); },
        blot_parse_ast::tag_field => { return expression(self_, node.b, depth + 1); },
        blot_parse_ast::tag_product, blot_parse_ast::tag_record, blot_parse_ast::tag_array, blot_parse_ast::tag_block => {
            if node.tag == blot_parse_ast::tag_block && node.c != 0 { return blot_error::Error.unsafe_cleanup; } for child in self_.engine.tree.children(id) { let error = expression(self_, child, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        blot_parse_ast::tag_let_stmt => { let binding = self_.engine.tree.binding(id); if binding.fallback != 0 { return blot_error::Error.unsafe_cleanup; } return expression(self_, binding.value, depth + 1); },
        blot_parse_ast::tag_if_expr, blot_parse_ast::tag_if_stmt => { let error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } let error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.c, depth + 1); },
        blot_parse_ast::tag_range_stmt => { return range(self_, node.a, node.b, node.c, depth + 1); },
        blot_parse_ast::tag_for_stmt => { let details = self_.engine.tree.extra.items[node.c..node.c + 3]; if details[0] == 0 { return blot_error::Error.unsafe_cleanup; } return range(self_, node.b, details[0], details[1], depth + 1); },
        _ => { return blot_error::Error.unsafe_cleanup; },
    } return blot_error::Error.none;
}
fn sourceRecipe<E>(engine: E, root: blot_parse_ast::Id, transferred: bool) -> SourceReceipt {
    var walker = SourceWalker<E> { engine: engine, transferred: transferred , ..}; var direct = root;
    while engine.tree.node(direct).tag == blot_parse_ast::tag_group { direct = engine.tree.node(direct).a; }
    if engine.tree.node(direct).tag != blot_parse_ast::tag_lambda { let host = sourceHost(engine, direct); return SourceReceipt { host, host , ..}; }
    if expression(walker, engine.tree.node(direct).b, 0) != blot_error::Error.none { return SourceReceipt {..}; } return SourceReceipt { true, walker.host , ..};
}
fn immutable(module: const blot_check_core::Module&, root: blot_check_core::Id) -> Error { return immutableRecipe(module, root, false, null); }
fn immutableTransferred(module: const blot_check_core::Module&, root: blot_check_core::Id) -> Error { return immutableRecipe(module, root, true, null); }
fn immutableScalarWithBudget(module: const blot_check_core::Module&, root: blot_check_core::Id, remaining: i64&) -> Error {
    if remaining < 8 { remaining = 0; return blot_error::Error.unsafe_cleanup; } remaining -= 8;
    if root == 0 || root >= module.nodes.len || module.node(root).tag != blot_check_core::Tag.closure || !typeBound(module.types, module.typeOf(root)) { return blot_error::Error.unsafe_cleanup; }
    let n = module.node(root); if n.op != blot_check_core::Op.none || n.b != 0 || n.c != 0 || n.a >= module.closures.len { return blot_error::Error.unsafe_cleanup; } let closure = module.closures[n.a];
    if closure.body == 0 || closure.body >= module.nodes.len || !typeBound(module.types, module.typeOf(closure.body)) || !typeBound(module.types, closure.parameter.ty) { return blot_error::Error.unsafe_cleanup; }
    let wrapper = module.types.node(module.typeOf(root)); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_cleanup || wrapper.c != 0 || !typeBound(module.types, wrapper.a) { return blot_error::Error.unsafe_cleanup; }
    let arrow = module.types.node(wrapper.a); if arrow.tag != blot_check_types::Tag.function || arrow.b != blot_check_types::unit || arrow.c != 0 || !typeBound(module.types, arrow.a) { return blot_error::Error.unsafe_cleanup; }
    let owner = module.types.node(arrow.a); if owner.tag != blot_check_types::Tag.usage || owner.b != blot_parse_ast::usagekind_unique || owner.c != 0 || !typeBound(module.types, owner.a) { return blot_error::Error.unsafe_cleanup; }
    let payload = module.types.node(owner.a); if !scalar(payload.tag) || payload.a != 0 || payload.b != 0 || payload.c != 0 { return blot_error::Error.unsafe_cleanup; } return immutableRecipe(module, root, false, remaining);
}
fn immutableRecipe(module: const blot_check_core::Module&, root: blot_check_core::Id, transferred: bool, remaining: i64?) -> Error {
    if immutableHost(module, root) { return blot_error::Error.none; } if root == 0 || root >= module.nodes.len || module.node(root).tag != blot_check_core::Tag.closure || module.node(root).a >= module.closures.len { return blot_error::Error.unsafe_cleanup; }
    let closure = module.closure(root); return immutableAdapter(module, module.typeOf(root), closure.parameter, closure.body, transferred, remaining);
}
struct CoreWalker { module: const blot_check_core::Module&, budget: Budget = Budget {..}, transferred: bool, host: bool = false }
recursive fn callable(self_: CoreWalker&, id: blot_check_core::Id, depth: i64) -> Error {
    let error = self_.budget.charge(depth); if error != blot_error::Error.none { return error; } if id == 0 || id >= self_.module.nodes.len { return blot_error::Error.unsafe_cleanup; } let node = self_.module.node(id);
    match node.tag {
        apply => { let error = callable(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.b, depth + 1); },
        reference => { if !immutableHost(self_.module, id) { return blot_error::Error.unsafe_cleanup; } self_.host = true; },
        primitive_function => { if node.a >= self_.module.primitives.len || node.op != blot_check_core::Op.none || node.b != 0 || node.c != 0 || self_.module.primitive(id).kind != blot_check_core::PrimitiveKind.scalar { return blot_error::Error.unsafe_cleanup; } },
        _ => { return blot_error::Error.unsafe_cleanup; },
    } return blot_error::Error.none;
}
recursive fn expression(self_: CoreWalker&, id: blot_check_core::Id, depth: i64) -> Error {
    if id == 0 { return blot_error::Error.none; } let error = self_.budget.charge(depth); if error != blot_error::Error.none { return error; } if id >= self_.module.nodes.len { return blot_error::Error.unsafe_cleanup; } let node = self_.module.node(id);
    match node.tag {
        constant, panic => {},
        reference => { if self_.transferred { let binding = self_.module.reference(id).binding; if binding == 0 || binding >= self_.module.bindings.len || (!immutableHost(self_.module, id) && (!transferableNominal(self_.module.types, self_.module.nominals, node.ty) || !transferableNominal(self_.module.types, self_.module.nominals, self_.module.bindings[binding].ty))) { return blot_error::Error.unsafe_cleanup; } } },
        scalar, logical, proof_guard => { let error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.b, depth + 1); },
        return_, usage_read => { return expression(self_, node.a, depth + 1); },
        bind => { return expression(self_, node.b, depth + 1); },
        product, record, array, block_, suite => { for child in self_.module.children(id) { let error = expression(self_, child, depth + 1); if error != blot_error::Error.none { return error; } } },
        if_value, if_stmt => { let error = expression(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } let error = expression(self_, node.b, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.c, depth + 1); },
        loop_ => { return finiteLoop(self_, id, depth); },
        apply => { let error = callable(self_, node.a, depth + 1); if error != blot_error::Error.none { return error; } return expression(self_, node.b, depth + 1); },
        _ => { return blot_error::Error.unsafe_cleanup; },
    } return blot_error::Error.none;
}
fn finiteLoop(self_: CoreWalker&, id: blot_check_core::Id, depth: i64) -> Error {
    let node = self_.module.node(id); if node.a >= self_.module.loops.len || node.b != 0 || node.c != 0 || node.ty != blot_check_types::unit { return blot_error::Error.unsafe_cleanup; } let loop_ = self_.module.loopInfo(id);
    if loop_.kind != blot_check_core::LoopKind.range || loop_.carries.len != 0 || loop_.first == 0 || loop_.end == 0 || loop_.body == 0 || loop_.body >= self_.module.nodes.len || loop_.first >= self_.module.nodes.len || loop_.end >= self_.module.nodes.len { return blot_error::Error.unsafe_cleanup; }
    let first = self_.module.node(loop_.first); let end = self_.module.node(loop_.end);
    if first.tag != blot_check_core::Tag.constant || end.tag != blot_check_core::Tag.constant || first.ty != blot_check_types::u32_type || end.ty != blot_check_types::u32_type || first.op != blot_check_core::Op.none || end.op != blot_check_core::Op.none || first.b != 0 || first.c != 0 || end.b != 0 || end.c != 0 { return blot_error::Error.unsafe_cleanup; }
    var iterations: u32 = 0; if first.a < end.a { iterations = end.a - first.a; } let before = self_.budget.remaining;
    let error = self_.budget.charge(depth + 1); if error != blot_error::Error.none { return error; } let error = expression(self_, loop_.body, depth + 1); if error != blot_error::Error.none { return error; } return self_.budget.repeat(before, iterations);
}
fn immutableAdapter(module: const blot_check_core::Module&, ty: Id, parameter: blot_check_core::Parameter, body: blot_check_core::Id, transferred: bool, remaining: i64?) -> Error {
    var walker = CoreWalker { module: module, transferred: transferred , ..}; { let optional_binding_74 .= remaining; if optional_binding_74 { let budget .= optional_binding_74; walker.budget.remaining = budget;  } }
    let error = checkAdapter(walker, ty, parameter, body); { let optional_binding_73 .= remaining; if optional_binding_73 { let budget .= optional_binding_73; budget = walker.budget.remaining;  } } return error;
}
fn equalType(module: const blot_check_core::Module&, left: Id, right: Id) -> bool { let equal, error = blot_check_rank_equal::equal(module.types, left, right, true); return error == blot_error::Error.none && equal; }
fn checkAdapter(walker: CoreWalker&, ty: Id, parameter: blot_check_core::Parameter, body: blot_check_core::Id) -> Error {
    let module = walker.module;
    if (!pureNominal(module.types, module.nominals, ty) && !hostNominal(module.types, module.nominals, ty)) || body == 0 || body >= module.nodes.len || !typeBound(module.types, parameter.ty) { return blot_error::Error.unsafe_cleanup; }
    let header = module.types.node(module.types.node(ty).a);
    if !equalType(module, header.a, parameter.ty) || (module.typeOf(body) != blot_check_types::never && !equalType(module, header.b, module.typeOf(body))) { return blot_error::Error.unsafe_cleanup; }
    let error = expression(walker, body, 0); if error != blot_error::Error.none { return error; } if walker.host != (header.c != 0) { return blot_error::Error.unsafe_cleanup; } return blot_error::Error.none;
}
fn validate(module: const blot_check_core::Module&) -> Error {
    if closedStorage(module) != blot_error::Error.none { return blot_error::Error.invalid_artifact; } var owned: Id[4096]=[0;4096]; var count: i64 = 0; var budget = Budget {..};
    for node, id in module.nodes {
        if budget.charge(0) != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
        if node.tag == blot_check_core::Tag.resource_scope || node.tag == blot_check_core::Tag.resource_acquire { if count == owned.len || node.b == 0 || node.b >= module.nodes.len { return blot_error::Error.invalid_artifact; } owned[count] = module.typeOf(node.b); count += 1; }
        if node.tag == blot_check_core::Tag.bind {
            if node.a == 0 || node.a >= module.bindings.len || node.b == 0 || node.b >= module.nodes.len { return blot_error::Error.invalid_artifact; } let binding = module.bindings[node.a];
            if pureNominal(module.types, module.nominals, binding.ty) { let value = module.node(node.b); if value.tag != blot_check_core::Tag.closure || value.a >= module.closures.len { return blot_error::Error.invalid_artifact; } let closure = module.closure(node.b); var actual = module.typeOf(node.b);
                if !typeBound(module.types, actual) { return blot_error::Error.invalid_artifact; } if module.types.node(actual).tag == blot_check_types::Tag.usage { actual = module.types.node(actual).a; }
                if !typeBound(module.types, actual) || !equalType(module, module.types.node(binding.ty).a, actual) { return blot_error::Error.invalid_artifact; }
                if immutableAdapter(module, binding.ty, closure.parameter, closure.body, false, null) != blot_error::Error.none { return blot_error::Error.invalid_artifact; } if count == owned.len { return blot_error::Error.invalid_artifact; } owned[count] = binding.ty; count += 1;
            }
        }
        if !typeBound(module.types, node.ty) { return blot_error::Error.invalid_artifact; } let wrapper = module.types.node(node.ty); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_cleanup { continue; }
        if node.tag != blot_check_core::Tag.closure && !immutableHost(module, id as u32) { return blot_error::Error.invalid_artifact; } if immutable(module, id as u32) != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
        if node.tag == blot_check_core::Tag.closure { if count == owned.len { return blot_error::Error.invalid_artifact; } owned[count] = node.ty; count += 1; }
    }
    for body, body_index in module.bodies {
        if budget.charge(0) != blot_error::Error.none { return blot_error::Error.invalid_artifact; } if body.binding == 0 { continue; } if body.binding >= module.bindings.len { return blot_error::Error.invalid_artifact; } let binding = module.bindings[body.binding]; if !typeBound(module.types, binding.ty) { return blot_error::Error.invalid_artifact; } let wrapper = module.types.node(binding.ty);
        if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_cleanup { continue; }
        if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id != body_index || !body.is_function || body.parameters.len != 1 || body.parameters.start >= module.parameters.len || !pureNominal(module.types, module.nominals, binding.ty) { return blot_error::Error.invalid_artifact; }
        let parameter = module.parameters[body.parameters.start]; if parameter.binding == 0 || parameter.binding >= module.bindings.len || module.bindings[parameter.binding].kind != blot_reuse_principal_interface::Kind.parameter || !typeBound(module.types, parameter.ty) || !typeBound(module.types, module.bindings[parameter.binding].ty) || !equalType(module, parameter.ty, module.bindings[parameter.binding].ty) { return blot_error::Error.invalid_artifact; }
        if !pureNominal(module.types, module.nominals, binding.scheme.root) || !pureNominal(module.types, module.nominals, body.scheme.root) || !equalType(module, binding.ty, binding.scheme.root) || !equalType(module, binding.ty, body.scheme.root) { return blot_error::Error.invalid_artifact; }
        if immutableAdapter(module, binding.ty, parameter, body.root, false, null) != blot_error::Error.none { return blot_error::Error.invalid_artifact; } if count == owned.len { return blot_error::Error.invalid_artifact; } owned[count] = binding.ty; count += 1;
    }
    for node, id in module.types.nodes {
        if node.tag != blot_check_types::Tag.usage || node.b != blot_parse_ast::usagekind_cleanup { continue; } if !pureNominal(module.types, module.nominals, id as u32) && !hostNominal(module.types, module.nominals, id as u32) { return blot_error::Error.invalid_artifact; }
        var witnessed = false; for index in 0..count { if budget.charge(0) != blot_error::Error.none { return blot_error::Error.invalid_artifact; } let equal, error = blot_check_rank_equal::equal(module.types, owned[index], id as u32, true); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } if equal { witnessed = true; } }
        if !witnessed && hostNominal(module.types, module.nominals, id as u32) { for parameter in module.parameters { if budget.charge(0) != blot_error::Error.none { return blot_error::Error.invalid_artifact; } if parameter.ty == id && parameter.binding != 0 && parameter.binding < module.bindings.len && module.bindings[parameter.binding].kind == blot_reuse_principal_interface::Kind.parameter { witnessed = true; } } }
        if !witnessed { return blot_error::Error.invalid_artifact; }
    } return blot_error::Error.none;
}
