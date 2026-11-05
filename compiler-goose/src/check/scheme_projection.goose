// Closed associated endpoints require the exact called goal and selected member.
namespace blot_check_scheme_projection;
import reuse.principal_interface;

import check.core;
import check.package_contracts;
import check.package_row_facts;
import check.types;
import support.error;
import support.structural_adapters;

import support.structural;
type Error = blot_error::Error;
struct Resolver {
    module: const blot_check_core::Module&, producer: const blot_check_core::Module&, binding: blot_check_core::BindingId,
    applied: const blot_check_package_contracts::Principal? = null,
}
fn resolver(self_: Resolver&) -> Resolver& { return self_; }
fn charge(remaining: i64&) -> Error { if remaining == 0 { return blot_error::Error.invalid_artifact; } remaining -= 1; return blot_error::Error.none; }
fn validate(self_: Resolver&, mapping: blot_check_package_contracts::Principal&, expected: blot_check_types::Id, actual: blot_check_types::Id) -> Error {
    var owner_mapping: const blot_check_package_contracts::Principal&  = mapping; { let optional_binding_36 .= self_.applied; if optional_binding_36 { let applied .= optional_binding_36; owner_mapping .= applied;  } }
    if !blot_check_package_contracts::sameTypes(owner_mapping.left, self_.producer.types) || !blot_check_package_contracts::sameTypes(owner_mapping.right, self_.module.types) || !blot_check_package_contracts::sameTypes(mapping.right, self_.module.types) { return blot_error::Error.invalid_artifact; }
    if self_.binding == 0 || self_.binding >= self_.producer.bindings.len { return blot_error::Error.invalid_artifact; }
    let callee = self_.producer.binding(self_.binding); let scheme = callee.scheme; var source_public = false;
    { let optional_binding_35 .= mapping.views; if optional_binding_35 { let views .= optional_binding_35; source_public = views.source_instances && views.large_plain_graph && self_.producer.types.node(scheme.root).tag != blot_check_types::Tag.forall && (scheme.variables.len > 128 || scheme.row_variables.len > 128);  } }
    var endpoint_variables = scheme.variables; var endpoint_rows = scheme.row_variables; if source_public { endpoint_variables = callee.public_variables; endpoint_rows = callee.public_rows; }
    if owner_mapping.instance != endpoint_variables || owner_mapping.instance_rows != endpoint_rows { return blot_error::Error.invalid_artifact; }
    let projection = mapping.left.node(expected); if projection.tag != blot_check_types::Tag.projection { return blot_error::Error.invalid_artifact; }
    let arguments = mapping.left.nominalArguments(projection); let member_name = mapping.left.projectionMember(projection);
    { let optional_binding_34 .= mapping.views; if optional_binding_34 { let views .= optional_binding_34;
        let pure_rows = views.pure_rows; let closed_rows = views.closed_rows;
        let error = selectProjection(self_, mapping, owner_mapping, projection, arguments, member_name, actual, pure_rows, closed_rows);
        views.pure_rows = pure_rows; views.closed_rows = closed_rows; return error;
     } } return blot_error::Error.invalid_artifact;
}
fn selectProjection(self_: Resolver&, mapping: blot_check_package_contracts::Principal&, owner_mapping: const blot_check_package_contracts::Principal&, projection: blot_check_types::Node, arguments: const blot_check_types::Id[:], member_name: u32, actual: blot_check_types::Id, pure_rows: blot_check_package_row_facts::Facts, closed_rows: blot_check_package_row_facts::Facts) -> Error {
    let scheme = self_.producer.binding(self_.binding).scheme;
    { let optional_binding_33 .= mapping.views; if optional_binding_33 { let views .= optional_binding_33;
        for goal in self_.producer.obligations[scheme.obligations.start..scheme.obligations.start + scheme.obligations.len] {
            let error = charge(mapping.remaining); if error != blot_error::Error.none { return error; } views.pure_rows = pure_rows; views.closed_rows = closed_rows;
            if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != projection.a || goal.identity.decl != projection.b { continue; }
            let tuple = self_.producer.types.node(goal.ty); if tuple.tag != blot_check_types::Tag.product || tuple.b != arguments.len { continue; }
            let required = self_.producer.types.list(blot_check_types::List { tuple.a, tuple.b , ..});
            var owned = blot_check_package_contracts::Principal { left: self_.producer.types, right: self_.producer.types, remaining: mapping.remaining, left_rows: scheme.closed_rows , ..};
            if self_.applied != null { owned = owner_mapping; owned.foreign_views = false; } var matches = true;
            for clause, index in required { let error = owned.validate(clause, arguments[index]); if error != blot_error::Error.none { if mapping.remaining == 0 { return blot_error::Error.invalid_artifact; } matches = false; break; } }
            if self_.applied != null && (!blot_structural::equal(owned.witnesses, owner_mapping.witnesses) || !blot_structural::equal(owned.scheme_row_witnesses, owner_mapping.scheme_row_witnesses)) { matches = false; } if !matches { continue; }
            for proof in self_.module.selected_proofs {
                let error = charge(mapping.remaining); if error != blot_error::Error.none { return error; } views.pure_rows = pure_rows; views.closed_rows = closed_rows;
                if proof.kind != blot_reuse_principal_interface::SelectedProofKind.implementation || proof.contract.unit != goal.identity.unit || proof.contract.decl != goal.identity.decl || proof.arguments.len != arguments.len { continue; }
                var comparison = owner_mapping; comparison.foreign_views = false; matches = true; let selected_arguments = self_.module.types.list(proof.arguments);
                for clause, index in required { let error = comparison.validate(clause, selected_arguments[index]); if error != blot_error::Error.none { if mapping.remaining == 0 { return blot_error::Error.invalid_artifact; } matches = false; break; } }
                if !matches || !blot_structural::equal(comparison.witnesses, owner_mapping.witnesses) || !blot_structural::equal(comparison.scheme_row_witnesses, owner_mapping.scheme_row_witnesses) { continue; }
                var declaration: const blot_check_core::Contract? = null;
                for candidate in self_.module.contracts { let error = charge(mapping.remaining); if error != blot_error::Error.none { return error; } if candidate.identity == goal.identity { declaration .= candidate; break; } }
                { let optional_binding_32 .= declaration; if optional_binding_32 { let declaration .= optional_binding_32;
                    if declaration.members.len != proof.members.len { return blot_error::Error.invalid_artifact; }
                    let members = self_.module.contract_members[declaration.members.start..declaration.members.start + declaration.members.len]; let selected = self_.module.selected_members[proof.members.start..proof.members.start + proof.members.len];
                    for member, index in members { let error = charge(mapping.remaining); if error != blot_error::Error.none { return error; } if member.name != member_name { continue; } let selected = selected[index];
                        if member.kind == blot_reuse_principal_interface::ContractMemberKind.value || selected.kind != blot_reuse_principal_interface::ImplementationMemberKind.type_ || selected.name != member_name { return blot_error::Error.invalid_artifact; }
                        var endpoint = blot_check_package_contracts::Principal { left: self_.module.types, right: self_.module.types, remaining: mapping.remaining, views: mapping.views , ..}; return endpoint.validate(selected.root, actual);
                    } return blot_error::Error.invalid_artifact;
                 } } return blot_error::Error.invalid_artifact;
            }
        }
     } } return blot_error::Error.invalid_artifact;
}
