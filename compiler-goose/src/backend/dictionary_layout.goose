// Opaque carriers follow a checked owner without publishing concrete equations.
namespace blot_backend_dictionary_layout;
import check.core;
import check.types;
import check.package_contracts;
import check.dictionary_owner;
import reuse.principal_interface;
import eval.specialization;
import .layout;
import .substitution_buffers;
import support.error;
import support.option;
type Error = blot_error::Error;
type Mapping = blot_backend_layout::Mapping;
fn step(remaining: i64&) -> Error { if remaining == 0 { return blot_error::Error.invalid_artifact; } remaining--; return blot_error::Error.none; }
fn mappingItems(mappings: Mapping[>..<]&) -> const Mapping[:] { mappings }
fn mappingItems(mappings: blot_backend_substitution_buffers::Mappings&) -> const Mapping[:] { mappings.items }
fn mappingItems(mappings: blot_eval_specialization::MappingSink&) -> const Mapping[:] { blot_eval_specialization::mappingItems(mappings) }
fn append(mappings: Mapping[>..<]&,mapping: Mapping) -> Error { mappings.push(mapping); return blot_error::Error.none; }
fn append(mappings: blot_backend_substitution_buffers::Mappings&,mapping: Mapping) -> Error { mappings.push(mapping) }
fn append(mappings: blot_eval_specialization::MappingSink&,mapping: Mapping) -> Error { blot_eval_specialization::appendSink(mappings,mapping) }
fn bind<M>(module: const blot_check_core::Module&,layouts: blot_backend_layout::Store&,mappings: M&,quantifier: u32,opening: u32,opened: blot_check_types::List,declared: bool) -> Error { bindOwner(module,layouts,mappings,blot_check_dictionary_owner::Owner.quantified { quantifier , ..},opening,opened,declared) }
fn bindOwner<M>(module: const blot_check_core::Module&,layouts: blot_backend_layout::Store&,mappings: M&,dictionary: blot_check_dictionary_owner::Owner,opening: u32,opened: blot_check_types::List,declared: bool) -> Error {
    if dictionary.count(module) == 0 { return blot_error::Error.none; } var has_projection = false; for node in module.types.nodes { if node.tag == blot_check_types::Tag.projection { has_projection = true; break; } } if !has_projection { return blot_error::Error.none; } var remaining: i64 = 65536; var scopes = blot_check_package_contracts::Context { types: module.types,remaining: remaining , ..}; let initialized = scopes.initialize(); if initialized != blot_error::Error.none { return initialized; } let formals = dictionary.formals(module);
    if opening == 0 { let entered = dictionary.enter(module,scopes); if entered != blot_error::Error.none { return entered; } } else { match dictionary { quantified selected=>{ let opened_scope = scopes.open(selected.value,opening,opened,module.binding(opening).ty); if opened_scope != blot_error::Error.none { return opened_scope; } },scheme=>{ return blot_error::Error.invalid_artifact; }, } }
    for ordinal in 0..dictionary.count(module) {
        let goal = dictionary.goal(module,ordinal); let charged = step(remaining); if charged != blot_error::Error.none { return charged; } if goal.kind != blot_check_types::ObligationKind.contract { return blot_error::Error.invalid_artifact; } var declaration = blot_support::none<blot_check_core::Contract>(); for candidate in module.contracts { if candidate.identity.unit == goal.identity.unit && candidate.identity.decl == goal.identity.decl { declaration = blot_support::some(candidate); break; } } if !declaration.present { return blot_error::Error.invalid_artifact; } let contract = declaration.value; let tuple = module.types.node(goal.ty);
        if tuple.tag != blot_check_types::Tag.product || tuple.b != contract.parameters.len || contract.variables.len > 128 { return blot_error::Error.invalid_artifact; } let arguments = module.types.list(blot_check_types::List { tuple.a,tuple.b , ..}); var replacements: u32[128] = [0;128];
        if declared { var selector = blot_check_package_contracts::Principal { left: module.types,right: module.types,remaining: remaining,views: scopes , ..}; for parameter,index in module.types.list(contract.parameters) { let substituted = selector.substituted(contract.variables,replacements[..contract.variables.len],parameter,arguments[index]); if substituted != blot_error::Error.none { return substituted; } for witness,index in selector.witnesses[..contract.variables.len] { replacements[index] = witness; } } }
        for projection,id in module.types.nodes {
            let charged = step(remaining); if charged != blot_error::Error.none { return charged; } if projection.tag != blot_check_types::Tag.projection || projection.a != goal.identity.unit || projection.b != goal.identity.decl { continue; } let member = module.types.projectionMember(projection); var allowed = false; for candidate in module.contract_members[contract.members.start..contract.members.start + contract.members.len] { if candidate.name == member && candidate.kind != blot_reuse_principal_interface::ContractMemberKind.value { allowed = true; break; } } if !allowed { continue; }
            let actuals = module.types.nominalArguments(projection); if actuals.len != arguments.len { continue; } var matches = true;
            for argument,index in arguments { var comparison = blot_check_package_contracts::Principal { left: module.types,right: module.types,remaining: remaining,views: scopes , ..}; var compared: Error; if declared { compared = comparison.substituted(contract.variables,replacements[..contract.variables.len],actuals[index],argument); } else { compared = comparison.substituted(formals,module.types.list(opened),argument,actuals[index]); } if compared != blot_error::Error.none { if remaining == 0 { return blot_error::Error.invalid_artifact; } matches = false; break; } }
            if !matches { continue; } let canonical,canonical_error = dictionary.canonicalGoal(module,ordinal,scopes); if canonical_error != blot_error::Error.none { return canonical_error; } let physical,physical_error = layouts.internAssociated(canonical as u32,member,0); if physical_error != blot_error::Error.none { return physical_error; } var found = false;
            for mapping in mappingItems(mappings) { if mapping.variable == id { if mapping.layout != physical { return blot_error::Error.invalid_artifact; } found = true; } } if !found { let appended = append(mappings,Mapping { variable: id as u32,layout: physical , ..}); if appended != blot_error::Error.none { return appended; } }
        }
    } return blot_error::Error.none;
}
