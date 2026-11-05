// Slots belong to immutable quantifiers or named principals.
namespace blot_check_dictionary_owner;
import check.core;
import check.package_contracts;
import check.types;
import reuse.principal_interface;
import support.error;
import support.option;

enum Owner { quantified { value: blot_check_types::Id }, scheme { value: blot_check_core::BindingId } }
fn forBinding(module: const blot_check_core::Module&, binding: blot_check_core::BindingId) -> blot_support::Option<Owner> {
    if binding == 0 || binding >= module.bindings.len { return blot_support::Option<Owner> { false, default<Owner>() , ..}; }
    let principal = module.bindings[binding]; if principal.ty == 0 { return blot_support::Option<Owner> { false, default<Owner>() , ..}; }
    var owner = Owner.scheme { binding , ..}; if module.types.node(principal.ty).tag == blot_check_types::Tag.forall { owner = Owner.quantified { principal.ty , ..}; }
    for ordinal in count(owner, module) { if goal(owner, module, ordinal).kind == blot_check_types::ObligationKind.contract { return blot_support::Option<Owner> { true, owner , ..}; } }
    return blot_support::Option<Owner> { false, default<Owner>() , ..};
}
fn count(self_: Owner, module: const blot_check_core::Module&) -> i64 {
    match self_ { quantified v => { return module.types.quantifierGoals(v.value).len; }, scheme v => { return module.bindings[v.value].scheme.obligations.len; }, }
}
fn goal(self_: Owner, module: const blot_check_core::Module&, ordinal: i64) -> blot_check_core::Obligation {
    match self_ {
        quantified v => {
            let value = module.types.quantifierGoals(v.value)[ordinal];
            return blot_check_core::Obligation { ty: value.ty, kind: value.kind, span: blot_check_core::Span { 0, 0 , ..},
                name: value.name, result: value.result, other: value.other, signature: value.signature,
                operator: value.operator, identity: value.identity, explicit: value.explicit , ..};
        },
        scheme v => { let range = module.bindings[v.value].scheme.obligations; return module.obligations[range.start + ordinal]; },
    }
}
fn formals(self_: Owner, module: const blot_check_core::Module&) -> blot_check_types::List {
    match self_ { quantified v => { let node = module.types.node(v.value); return blot_check_types::List { node.b, node.c , ..}; }, scheme v => { return module.bindings[v.value].scheme.variables; }, }
}
fn enter(self_: Owner, module: const blot_check_core::Module&, scopes: blot_check_package_contracts::Context&) -> blot_error::Error {
    match self_ { quantified v => { return scopes.enter(v.value); }, scheme v => { return scopes.generic(module.bindings[v.value].scheme); }, }
}
fn instantiate(self_: Owner, module: const blot_check_core::Module&, proof: blot_check_package_contracts::Principal&, actual: blot_check_types::Id) -> blot_error::Error {
    match self_ {
        quantified v => { let error = proof.instantiateTypes(v.value, actual); if error != blot_error::Error.none { return error; } },
        scheme v => { let error = proof.instantiateScheme(module.bindings[v.value].scheme, actual); if error != blot_error::Error.none { return error; } },
    }
    let formals_ = module.types.list(formals(self_, module)); if formals_.len > proof.witnesses.len { return blot_error::Error.invalid_artifact; }
    for formal, i in formals_ { let witness = proof.witnesses[i]; let leaf = module.types.node(formal);
        if witness == 0 && (leaf.tag == blot_check_types::Tag.variable || (leaf.tag == blot_check_types::Tag.bound && leaf.b == 0)) { return blot_error::Error.invalid_artifact; }
    }
    return blot_error::Error.none;
}
fn step(remaining: i64&) -> blot_error::Error { if remaining == 0 { return blot_error::Error.invalid_artifact; } remaining -= 1; return blot_error::Error.none; }
fn canonicalGoal(self_: Owner, module: const blot_check_core::Module&, ordinal: i64,
                  scopes: blot_check_package_contracts::Context&) -> i64, blot_error::Error {
    let value = goal(self_, module, ordinal); if value.kind != blot_check_types::ObligationKind.contract { return 0, blot_error::Error.invalid_artifact; }
    for prior in ordinal {
        let charged = step(scopes.remaining); if charged != blot_error::Error.none { return 0, charged; }
        let candidate = goal(self_, module, prior);
        if candidate.kind != blot_check_types::ObligationKind.contract || candidate.identity.unit != value.identity.unit || candidate.identity.decl != value.identity.decl { continue; }
        var proof = blot_check_package_contracts::Principal { left: module.types, right: module.types, remaining: scopes.remaining, views: scopes , ..};
        let error = proof.validate(value.ty, candidate.ty);
        if error != blot_error::Error.none { if scopes.remaining == 0 { return 0, blot_error::Error.invalid_artifact; } continue; }
        return prior, blot_error::Error.none;
    }
    return ordinal, blot_error::Error.none;
}
fn offset(self_: Owner, module: const blot_check_core::Module&, wanted_goal: i64, wanted_member: i64, remaining: i64&) -> i64, blot_error::Error {
    if wanted_goal >= count(self_, module) { return 0, blot_error::Error.invalid_artifact; } var result: i64 = 1;
    for ordinal in count(self_, module) {
        let charged = step(remaining); if charged != blot_error::Error.none { return 0, charged; }
        let value = goal(self_, module, ordinal); if value.kind != blot_check_types::ObligationKind.contract { continue; }
        var found: i64 = -1;
        for candidate, index in module.contracts {
            let charged = step(remaining); if charged != blot_error::Error.none { return 0, charged; }
            if candidate.identity.unit == value.identity.unit && candidate.identity.decl == value.identity.decl { found = index; break; }
        }
        if found < 0 { return 0, blot_error::Error.invalid_artifact; } let contract = module.contracts[found];
        for member, index in module.contract_members[contract.members.start..contract.members.start + contract.members.len] {
            let charged = step(remaining); if charged != blot_error::Error.none { return 0, charged; }
            if ordinal == wanted_goal && index == wanted_member {
                if member.kind != blot_reuse_principal_interface::ContractMemberKind.value { return 0, blot_error::Error.invalid_artifact; }
                return result, blot_error::Error.none;
            }
            if member.kind == blot_reuse_principal_interface::ContractMemberKind.value { result += 1; }
        }
    }
    return 0, blot_error::Error.invalid_artifact;
}
