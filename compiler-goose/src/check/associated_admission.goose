// Scope and publication checks reconstruct declaration-owned associated types.
namespace blot_check_associated_admission;
import check.core;
import check.frozen_types;
import check.numeric_proof_headers;
import check.rank_portable;
import check.types;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.principal_type_graph;
import support.error;
import support.native;

import support.structural;
import std;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type List = blot_check_types::List;
type Source = blot_check_frozen_types::Source;
type Types = blot_check_core::Types;
type Copier = blot_reuse_principal_type_graph::FrozenCopy;
struct ScopeKey { id: u32, row: bool }
fn hash(value: ScopeKey) -> u64 { return ::hash_combine(::hash(value.id), ::hash(value.row)); }
struct Work { id: u32, row: bool = false, depth: u32 = 0 }
fn charge(remaining: i64&) -> Error { if remaining == 0 { return blot_error::Error.invalid_artifact; } remaining -= 1; return blot_error::Error.none; }
fn convert(error: Error) -> Error { if error == blot_error::Error.none || error == blot_error::Error.out_of_memory { return error; } return blot_error::Error.invalid_artifact; }
fn boundType(source: Source, ids: List, variable: u32) -> bool { for id in source.list(ids) { let node = source.node(id); if node.tag == blot_check_types::Tag.variable && node.a == variable { return true; } } return false; }
fn boundRow<C>(source: Source, contract: C, variable: u32, member: bool) -> bool {
    if member { for id in source.list(contract.row_parameters) { match source.row(id).tail { variable match_payload_29 => { let value = match_payload_29.value;  if value == variable { return true; } }, _ => {}, } } return false; }
    for id in source.list(contract.row_variables) { if id == variable { return true; } } return false;
}
fn scope<C>(source: Source, contract: C, root: Id, member: bool, remaining: i64&) -> Error {
    var work: Work[>..<] = []; var seen: dictionary<ScopeKey,bool>   = dictionary<ScopeKey,bool> {}; work.push(Work { root , ..});
    while work.len != 0 { let item = work[work.len - 1]; work.resize(work.len - 1); let error = charge(remaining); if error != blot_error::Error.none { return error; } if item.depth >= 256 { return blot_error::Error.invalid_artifact; }
        let key = ScopeKey { item.id, item.row , ..}; if seen.contains(key) { continue; } seen.insert(key, true);
        if item.row { let row = source.row(item.id); match row.tail { variable match_payload_27 => { let value = match_payload_27.value;  if !boundRow(source, contract, value, member) { return blot_error::Error.invalid_artifact; } }, parameter match_payload_28 => { let value = match_payload_28.value;  return blot_error::Error.invalid_artifact; }, _ => {}, }
            for label in source.rowLabels(row.labels) { let error = charge(remaining); if error != blot_error::Error.none { return error; } for argument in source.list(source.operation(label).arguments) { work.push(Work { id: argument, depth: item.depth + 1 , ..}); } } continue;
        }
        let n = source.node(item.id); let depth = item.depth + 1;
        match n.tag {
            variable => { if !boundType(source, contract.variables, n.a) { return blot_error::Error.invalid_artifact; } },
            function => { work.push(Work { id: n.a, depth: depth , ..}); work.push(Work { id: n.b, depth: depth , ..}); work.push(Work { n.c, true, depth , ..}); },
            provider => { work.push(Work { id: n.a, depth: depth , ..}); work.push(Work { n.c, true, depth , ..}); },
            usage, array, list, cursor, resolver => { work.push(Work { id: n.a, depth: depth , ..}); },
            state_provider => { work.push(Work { id: n.a, depth: depth , ..}); work.push(Work { id: n.b, depth: depth , ..}); work.push(Work { id: n.c, depth: depth , ..}); },
            product => { for id in source.list(List { n.a, n.b , ..}) { work.push(Work { id: id, depth: depth , ..}); } },
            record => { for index in 0..n.b { work.push(Work { id: source.recordField(n, index).ty, depth: depth , ..}); } },
            nominal, projection => { for id in source.nominalArguments(n) { work.push(Work { id: id, depth: depth , ..}); } },
            _ => {},
        }
    } return blot_error::Error.none;
}
fn interface(owner: const blot_reuse_principal_interface::Interface&) -> Error { var remaining: i64 = 1000000; return interfaceWithBudget(owner, remaining); }
fn interfaceWithBudget(owner: const blot_reuse_principal_interface::Interface&, remaining: i64&) -> Error {
    if owner.contract_members.len == 0 { return blot_error::Error.none; } let source = blot_check_frozen_types::Source.frozen { owner.graph , ..};
    var claimed: bool[>..] = []; claimed.resize(owner.contract_members.len, false); var identities: dictionary<blot_check_types::NominalIdentity,bool>   = dictionary<blot_check_types::NominalIdentity,bool> {};
    for contract in owner.contracts { let error = charge(remaining); if error != blot_error::Error.none { return error; } if identities.contains(contract.identity) { return blot_error::Error.invalid_artifact; } identities.insert(contract.identity, true);
        if contract.private && contract.name == 0 { continue; } if contract.identity.unit == 0 || contract.identity.decl != (blot_check_types::opaque_name_bit | contract.name) { return blot_error::Error.invalid_artifact; }
        for index in contract.members.start..contract.members.start + contract.members.len { if claimed[index] { return blot_error::Error.invalid_artifact; } claimed[index] = true; let error = scope(source, contract, owner.contract_members[index].root, true, remaining); if error != blot_error::Error.none { return error; } }
        for predicate in owner.contract_predicates[contract.predicates.start..contract.predicates.start + contract.predicates.len] { let endpoints: Id[4] = [predicate.ty, predicate.other, predicate.result, predicate.signature]; for endpoint in endpoints { let error = scope(source, contract, endpoint, false, remaining); if error != blot_error::Error.none { return error; } } }
    }
    for member, index in owner.contract_members { if !claimed[index] && (member.name != 0 || member.root != 0) { return blot_error::Error.invalid_artifact; } } return blot_error::Error.none;
}
fn typesView(graph: const blot_check_frozen_types::Graph&) -> Types {
    return Types { owner_id: blot_native::fresh_owner_id(), nodes: graph.nodes, extra: graph.extra, effects: blot_check_core::EffectRows { graph.rows, graph.labels, graph.row_variable_count , ..}, operations: graph.operations, quantifier_goals: graph.quantifier_goals, quantifier_obligations: graph.quantifier_obligations , ..};
}
fn graphView(types: const Types&) -> blot_check_frozen_types::Graph { return blot_check_frozen_types::Graph { types.nodes, types.extra, types.effects.rows, types.effects.labels, types.operations, types.effects.variable_count, types.quantifier_goals, types.quantifier_obligations , ..}; }
fn sameRoot(left: Copier&, right: Copier&, l: Id, r: Id, remaining: i64&) -> Error {
    let first, error = left.ty(l, 0); if error != blot_error::Error.none { return convert(error); } let second, error = right.ty(r, 0); if error != blot_error::Error.none { return convert(error); }
    left.destination.has_projections = true; left.destination.projection_limit = left.destination.projection_steps + remaining; let before = left.destination.projection_steps;
    let equal, error = left.destination.equalSymbolic(first, second); remaining -= min<i64>(remaining, left.destination.projection_steps - before);
    if error != blot_error::Error.none { return convert(error); } if !equal { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
fn withCopiers<C,F>(first:const Types&,second:const Types&,destination:blot_check_types::Store&,remaining:i64&,context:C&)->Error {
 let a=graphView(first);let b=graphView(second);let initialized,error=blot_reuse_principal_type_graph::initPooled(blot_check_frozen_types::Source.frozen{a, ..},destination,256,1000000,true,remaining);if error!=blot_error::Error.none {return error;}var left=initialized;let initialized,error=blot_reuse_principal_type_graph::initPooled(blot_check_frozen_types::Source.frozen{b, ..},destination,256,1000000,true,remaining);if error!=blot_error::Error.none {left.deinit();return error;}var right=initialized;let error=F(context,destination,left,right);left.deinit();right.deinit();return error;
}

struct Equivalence<L,R,LP,RP> {
    first: const Types&, second: const Types&, left_contract: L, right_contract: R,
    left_members: const blot_reuse_principal_interface::ContractMember[:], right_members: const blot_reuse_principal_interface::ContractMember[:],
    left_predicates: LP, right_predicates: RP, remaining: i64&,
}
fn equivalent<L,R,LP,RP>(first: const Types&, second: const Types&, left_contract: L, right_contract: R, left_members: const blot_reuse_principal_interface::ContractMember[:], right_members: const blot_reuse_principal_interface::ContractMember[:], left_predicates: LP, right_predicates: RP, remaining: i64&) -> Error {
    if left_contract.identity != right_contract.identity || left_contract.name != right_contract.name || left_contract.private != right_contract.private || left_contract.requires_implementation != right_contract.requires_implementation { return blot_error::Error.invalid_artifact; }
    if left_contract.row_parameters.len != right_contract.row_parameters.len || first.list(left_contract.row_parameter_names) != second.list(right_contract.row_parameter_names) { return blot_error::Error.invalid_artifact; }
    if left_contract.parameters.len != right_contract.parameters.len || left_contract.variables.len != right_contract.variables.len || left_contract.row_variables.len != right_contract.row_variables.len || left_members.len != right_members.len || left_predicates.len != right_predicates.len { return blot_error::Error.invalid_artifact; }
    var context = Equivalence<L,R,LP,RP> { first, second, left_contract, right_contract, left_members, right_members, left_predicates, right_predicates, remaining , ..};
    return convert(blot_check_types::withStore<Equivalence<L,R,LP,RP>>(context,equivalentStore));
}
fn equivalentStore<L,R,LP,RP>(self_: Equivalence<L,R,LP,RP>&, destination: blot_check_types::Store&) -> Error { return withCopiers<Equivalence<L,R,LP,RP>>(self_.first, self_.second, destination, self_.remaining, self_,equivalentCopies); }
fn bindVariables(left: Copier&, right: Copier&, first: const Types&, second: const Types&, xs: List, ys: List, rows: bool) -> Error {
    let a = first.list(xs); let b = second.list(ys); if a.len != b.len { return blot_error::Error.invalid_artifact; }
    for l, index in a {
        if rows { let fresh, error = left.rowVariable(l); if error != blot_error::Error.none { return convert(error); } right.row_variables.insert(b[index], fresh); }
        else { let fresh, error = left.ty(l, 0); if error != blot_error::Error.none { return convert(error); } right.variables.insert(second.node(b[index]).a, fresh); }
    } return blot_error::Error.none;
}
fn equivalentCopies<L,R,LP,RP>(self_: Equivalence<L,R,LP,RP>&, destination: blot_check_types::Store&, left: Copier&, right: Copier&) -> Error {
    let error = bindVariables(left, right, self_.first, self_.second, self_.left_contract.variables, self_.right_contract.variables, false); if error != blot_error::Error.none { return error; }
    let error = bindVariables(left, right, self_.first, self_.second, self_.left_contract.row_variables, self_.right_contract.row_variables, true); if error != blot_error::Error.none { return error; }
    let xs = self_.first.list(self_.left_contract.row_parameters); let ys = self_.second.list(self_.right_contract.row_parameters);
    for l, index in xs { let first, error = left.row(l, 0); if error != blot_error::Error.none { return convert(error); } let second, error = right.row(ys[index], 0); if error != blot_error::Error.none { return convert(error); }
        let first_type, error = destination.functionWithEffects(blot_check_types::unit, blot_check_types::unit, first); if error != blot_error::Error.none { return convert(error); } let second_type, error = destination.functionWithEffects(blot_check_types::unit, blot_check_types::unit, second); if error != blot_error::Error.none { return convert(error); }
        destination.has_projections = true; destination.projection_limit = destination.projection_steps + self_.remaining; let before = destination.projection_steps;
        let equal, error = destination.equalSymbolic(first_type, second_type); self_.remaining -= min(self_.remaining, destination.projection_steps - before); if error != blot_error::Error.none { return convert(error); } if !equal { return blot_error::Error.invalid_artifact; }
    }
    let xs = self_.first.list(self_.left_contract.parameters); let ys = self_.second.list(self_.right_contract.parameters); for l, index in xs { let error = sameRoot(left, right, l, ys[index], self_.remaining); if error != blot_error::Error.none { return error; } }
    for l, index in self_.left_members { let r = self_.right_members[index]; if l.contract != r.contract || l.name != r.name || l.kind != r.kind { return blot_error::Error.invalid_artifact; } let error = sameRoot(left, right, l.root, r.root, self_.remaining); if error != blot_error::Error.none { return error; } }
    for l, index in self_.left_predicates { let r = self_.right_predicates[index]; if l.kind != r.kind || l.name != r.name || l.operator != r.operator || l.identity != r.identity || l.explicit != r.explicit { return blot_error::Error.invalid_artifact; }
        let xs: Id[4] = [l.ty, l.other, l.result, l.signature]; let ys: Id[4] = [r.ty, r.other, r.result, r.signature]; for x, i in xs { let error = sameRoot(left, right, x, ys[i], self_.remaining); if error != blot_error::Error.none { return error; } }
    } return blot_error::Error.none;
}
struct GenerativeComparison { first: const Types&, second: const Types&, public: blot_check_types::Scheme, private: blot_check_types::Scheme, remaining: i64& }
fn generativeStore(self_: GenerativeComparison&, destination: blot_check_types::Store&) -> Error { return withCopiers<GenerativeComparison>(self_.first, self_.second, destination, self_.remaining, self_,generativeCopies); }
fn generativeCopies(self_: GenerativeComparison&, destination: blot_check_types::Store&, left: Copier&, right: Copier&) -> Error {
    let error = bindVariables(left, right, self_.first, self_.second, self_.public.variables, self_.private.variables, false); if error != blot_error::Error.none { return error; }
    let error = bindVariables(left, right, self_.first, self_.second, self_.public.row_variables, self_.private.row_variables, true); if error != blot_error::Error.none { return error; }
    let error = sameRoot(left, right, self_.public.root, self_.private.root, self_.remaining); if error != blot_error::Error.none { return error; }
    let xs = self_.first.list(self_.public.generative); let ys = self_.second.list(self_.private.generative); for x, index in xs { let error = sameRoot(left, right, x, ys[index], self_.remaining); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn publicCore(principal: const blot_reuse_principal_interface::Interface&, executable: const blot_check_core::Module&) -> Error { var remaining: i64 = 1000000; return publicCoreWithBudget(principal, executable, remaining); }
fn publicCoreWithBudget(principal: const blot_reuse_principal_interface::Interface&, executable: const blot_check_core::Module&, remaining: i64&) -> Error {
    let error = blot_check_rank_portable::publicCore(principal, executable); if error != blot_error::Error.none { return error; }
    for binding, index in principal.bindings { let private = executable.bindings[index].scheme; if binding.ty == 0 || (binding.scheme.generative.len == 0 && private.generative.len == 0) { continue; } let public = binding.scheme;
        if public.generative.len != private.generative.len || public.variables.len != private.variables.len || public.row_variables.len != private.row_variables.len { return blot_error::Error.invalid_artifact; }
        let source = typesView(principal.graph); var context = GenerativeComparison { source, executable.types, public, private, remaining , ..}; let error = blot_check_types::withStore<GenerativeComparison>(context,generativeStore); if error != blot_error::Error.none { return convert(error); }
    }
    for value in principal.proof_contracts { let error = charge(remaining); if error != blot_error::Error.none { return error; } { let optional_binding_63 .= blot_check_numeric_proof_headers::find(executable.proof_contracts, value.binding); if optional_binding_63 { let original .= optional_binding_63; if !blot_check_numeric_proof_headers::equal(value.header, original) { return blot_error::Error.invalid_artifact; }  } else { return blot_error::Error.invalid_artifact; } } }
    for binding, id in principal.bindings { if binding.ty == 0 { continue; } if blot_check_numeric_proof_headers::find(executable.proof_contracts, id as u32) != null && blot_check_numeric_proof_headers::find(principal.proof_contracts, id as u32) == null { return blot_error::Error.invalid_artifact; } }
    if principal.contract_members.len == 0 && executable.contract_members.len == 0 { return blot_error::Error.none; } let first = typesView(principal.graph);
    for contract in principal.contracts { if contract.private || contract.members.len == 0 { continue; } var original: const blot_check_core::Contract? = null; for candidate in executable.contracts { if contract.identity == candidate.identity { original .= candidate; break; } }
        { let optional_binding_62 .= original; if optional_binding_62 { let original .= optional_binding_62; let error = equivalent(first, executable.types, contract, original, principal.contract_members[contract.members.start..contract.members.start + contract.members.len], executable.contract_members[original.members.start..original.members.start + original.members.len], principal.contract_predicates[contract.predicates.start..contract.predicates.start + contract.predicates.len], executable.obligations[original.predicates.start..original.predicates.start + original.predicates.len], remaining); if error != blot_error::Error.none { return error; }  } else { return blot_error::Error.invalid_artifact; } }
    } return blot_error::Error.none;
}
fn originalProducers(owners: const blot_reuse_frozen_dependency::Module[:]) -> Error { var remaining: i64 = 1000000; return originalProducersWithBudget(owners, remaining); }
fn originalProducersWithBudget(owners: const blot_reuse_frozen_dependency::Module[:], remaining: i64&) -> Error {
    for owner in owners { for contract in owner.interface.contracts { if contract.private || contract.members.len == 0 { continue; } if contract.identity.unit == 0 || contract.identity.unit > owners.len { return blot_error::Error.invalid_artifact; } let producer = owners[contract.identity.unit - 1].interface;
        var original: const blot_reuse_principal_interface::Contract? = null; for candidate in producer.contracts { if candidate.identity == contract.identity && !candidate.private { original .= candidate; break; } }
        { let optional_binding_61 .= original; if optional_binding_61 { let original .= optional_binding_61; let first = typesView(owner.interface.graph); let second = typesView(producer.graph);
            let error = equivalent(first, second, contract, original, owner.interface.contract_members[contract.members.start..contract.members.start + contract.members.len], producer.contract_members[original.members.start..original.members.start + original.members.len], owner.interface.contract_predicates[contract.predicates.start..contract.predicates.start + contract.predicates.len], producer.contract_predicates[original.predicates.start..original.predicates.start + original.predicates.len], remaining); if error != blot_error::Error.none { return error; }
         } else { return blot_error::Error.invalid_artifact; } }
    } } return blot_error::Error.none;
}
