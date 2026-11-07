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
fn init(module:const blot_check_core::Module&,producer:const blot_check_core::Module&,binding:blot_check_core::BindingId,applied:const blot_check_package_contracts::Principal?=null)->Resolver {return Resolver{module:module,producer:producer,binding:binding,applied:applied};}
fn resolver(self_: Resolver&) -> Resolver& { return self_; }
fn charge(remaining: i64&) -> Error { if remaining == 0 { return blot_error::Error.invalid_artifact; } remaining -= 1; return blot_error::Error.none; }
type Types = blot_check_core::Types;
type Id = blot_check_types::Id;
type Context = blot_check_package_contracts::Context;
type Principal = blot_check_package_contracts::Principal;
type PrincipalState = blot_check_package_contracts::PrincipalState;
type CertificatePairs = blot_check_package_contracts::CertificatePairs;
type VersionPair = blot_check_package_contracts::VersionPair;
type Facts = blot_check_package_row_facts::Facts;

fn validate(self_: Resolver&, mapping: Principal&, expected: Id, actual: Id) -> Error {
    return validateMode(self_, mapping, mapping.left, mapping.right, mapping.remaining, mapping.views, mapping.certificate_pairs, mapping.version_pairs, mapping.projection_resolver, expected, actual);
}
recursive fn validateMode<P>(self_: Resolver&, mapping: P&, left_types: const Types&, right_types: const Types&, remaining: i64&, views: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: Resolver?, expected: Id, actual: Id) -> Error {
    let applied .= self_.applied;
    if applied {
        return validateOwner(self_, left_types, right_types, remaining, views, applied, applied.left, applied.right, applied.remaining, applied.views, applied.certificate_pairs, applied.version_pairs, applied.projection_resolver, expected, actual);
    }
    return validateOwner(self_, left_types, right_types, remaining, views, mapping, left_types, right_types, remaining, views, certificates, versions, projection_resolver, expected, actual);
}
recursive fn validateOwner<Q>(self_: Resolver&, left_types: const Types&, right_types: const Types&, remaining: i64&, views: Context?, owner_mapping: const Q&, owner_left: const Types&, owner_right: const Types&, owner_remaining: i64&, owner_views: Context?, owner_certificates: CertificatePairs?, owner_versions: const VersionPair[:], owner_resolver: Resolver?, expected: Id, actual: Id) -> Error {
    if !blot_check_package_contracts::sameTypes(owner_left, self_.producer.types) || !blot_check_package_contracts::sameTypes(owner_right, self_.module.types) || !blot_check_package_contracts::sameTypes(right_types, self_.module.types) { return blot_error::Error.invalid_artifact; }
    if self_.binding == 0 || self_.binding >= self_.producer.bindings.len { return blot_error::Error.invalid_artifact; }
    let callee = self_.producer.binding(self_.binding); let scheme = callee.scheme; var source_public = false;
    { let context .= views; if context { source_public = context.source_instances && context.large_plain_graph && self_.producer.types.node(scheme.root).tag != blot_check_types::Tag.forall && (scheme.variables.len > 128 || scheme.row_variables.len > 128); } }
    var endpoint_variables = scheme.variables; var endpoint_rows = scheme.row_variables; if source_public { endpoint_variables = callee.public_variables; endpoint_rows = callee.public_rows; }
    if owner_mapping.instance != endpoint_variables || owner_mapping.instance_rows != endpoint_rows { return blot_error::Error.invalid_artifact; }
    let projection = left_types.node(expected); if projection.tag != blot_check_types::Tag.projection { return blot_error::Error.invalid_artifact; }
    let arguments = left_types.nominalArguments(projection); let member_name = left_types.projectionMember(projection);
    { let context .= views; if context {
        let pure_rows = context.pure_rows; let closed_rows = context.closed_rows;
        let error = selectProjection(self_, remaining, views, owner_mapping, owner_left, owner_right, owner_remaining, owner_views, owner_certificates, owner_versions, owner_resolver, projection, arguments, member_name, actual, pure_rows, closed_rows);
        context.pure_rows = pure_rows; context.closed_rows = closed_rows; return error;
    } } return blot_error::Error.invalid_artifact;
}
recursive fn compareArguments<P,F>(comparison: P&, left_types: const Types&, right_types: const Types&, budget: i64&, views: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: Resolver?, required: const Id[:], arguments: const Id[:], remaining: i64&) -> bool, Error {
    for clause, index in required {
        let error = blot_check_package_contracts::validateMode(comparison, left_types, right_types, budget, views, certificates, versions, projection_resolver, clause, arguments[index], F);
        if error != blot_error::Error.none {
            if remaining == 0 { return false, blot_error::Error.invalid_artifact; }
            return false, blot_error::Error.none;
        }
    }
    return true, blot_error::Error.none;
}
recursive fn selectProjection<Q>(self_: Resolver&, remaining: i64&, context: Context?, owner_mapping: const Q&, owner_left: const Types&, owner_right: const Types&, owner_remaining: i64&, owner_views: Context?, owner_certificates: CertificatePairs?, owner_versions: const VersionPair[:], owner_resolver: Resolver?, projection: blot_check_types::Node, arguments: const Id[:], member_name: u32, actual: Id, pure_rows: Facts, closed_rows: Facts) -> Error {
    let scheme = self_.producer.binding(self_.binding).scheme;
    { let views .= context; if views {
        for goal in self_.producer.obligations[scheme.obligations.start..scheme.obligations.start + scheme.obligations.len] {
            let error = charge(remaining); if error != blot_error::Error.none { return error; } views.pure_rows = pure_rows; views.closed_rows = closed_rows;
            if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != projection.a || goal.identity.decl != projection.b { continue; }
            let tuple = self_.producer.types.node(goal.ty); if tuple.tag != blot_check_types::Tag.product || tuple.b != arguments.len { continue; }
            let required = self_.producer.types.list(blot_check_types::List { tuple.a, tuple.b , ..});
            var owned = PrincipalState { left_rows: scheme.closed_rows, ..};
            var matches = false;
            if self_.applied != null {
                owned = blot_check_package_contracts::principalState(owner_mapping); owned.foreign_views = false;
                let matched, error = compareArguments(owned, owner_left, owner_right, owner_remaining, owner_views, owner_certificates, owner_versions, owner_resolver, required, arguments, remaining, blot_check_package_contracts::resolvePrincipalProjectionMode);
                if error != blot_error::Error.none { return error; } matches = matched;
            } else {
                let matched, error = compareArguments(owned, self_.producer.types, self_.producer.types, remaining, null, null, default<const VersionPair[:]>(), null, required, arguments, remaining, blot_check_package_contracts::rejectPrincipalProjection);
                if error != blot_error::Error.none { return error; } matches = matched;
            }
            if self_.applied != null && (!blot_structural::equal(owned.witnesses, owner_mapping.witnesses) || !blot_structural::equal(owned.scheme_row_witnesses, owner_mapping.scheme_row_witnesses)) { matches = false; } if !matches { continue; }
            for proof in self_.module.selected_proofs {
                let error = charge(remaining); if error != blot_error::Error.none { return error; } views.pure_rows = pure_rows; views.closed_rows = closed_rows;
                if proof.kind != blot_reuse_principal_interface::SelectedProofKind.implementation || proof.contract.unit != goal.identity.unit || proof.contract.decl != goal.identity.decl || proof.arguments.len != arguments.len { continue; }
                var comparison = blot_check_package_contracts::principalState(owner_mapping); comparison.foreign_views = false;
                let selected_arguments = self_.module.types.list(proof.arguments);
                let matched, error = compareArguments(comparison, owner_left, owner_right, owner_remaining, owner_views, owner_certificates, owner_versions, owner_resolver, required, selected_arguments, remaining, blot_check_package_contracts::resolvePrincipalProjectionMode);
                if error != blot_error::Error.none { return error; } matches = matched;
                if !matches || !blot_structural::equal(comparison.witnesses, owner_mapping.witnesses) || !blot_structural::equal(comparison.scheme_row_witnesses, owner_mapping.scheme_row_witnesses) { continue; }
                var declaration: const blot_check_core::Contract? = null;
                for candidate,index in self_.module.contracts { let error = charge(remaining); if error != blot_error::Error.none { return error; } if candidate.identity == goal.identity { declaration .= self_.module.contracts[index]; break; } }
                { let selected_declaration .= declaration; if selected_declaration {
                    if selected_declaration.members.len != proof.members.len { return blot_error::Error.invalid_artifact; }
                    let members = self_.module.contract_members[selected_declaration.members.start..selected_declaration.members.start + selected_declaration.members.len]; let selected = self_.module.selected_members[proof.members.start..proof.members.start + proof.members.len];
                    for member, index in members { let error = charge(remaining); if error != blot_error::Error.none { return error; } if member.name != member_name { continue; } let selected = selected[index];
                        if member.kind == blot_reuse_principal_interface::ContractMemberKind.value || selected.kind != blot_reuse_principal_interface::ImplementationMemberKind.type_ || selected.name != member_name { return blot_error::Error.invalid_artifact; }
                        return blot_check_package_contracts::validateEndpoint(self_.module.types,remaining,context,selected.root,actual);
                    } return blot_error::Error.invalid_artifact;
                } } return blot_error::Error.invalid_artifact;
            }
        }
    } } return blot_error::Error.invalid_artifact;
}
