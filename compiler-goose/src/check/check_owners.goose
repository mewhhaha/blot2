// Concrete retained checker output ownership. No borrowed factory tables escape.
namespace blot_check_check;
import check.capability_contracts;
import check.generative_schemes;
import check.numeric_proof_bodies;
import check.numeric_proof_contracts;
import check.numeric_proof_terms;
import check.types;
import parse.ast;
import reuse.principal_interface;
import support.error;
import support.native;

import std;
import .check;
import .check_packet_owner;
struct CheckedOwner {lease:u32=0,generation:u64=0}
struct CheckedHeaderLease {
value_slots:u32[:]=default<u32[:]>(),
proof_slots:u32[:]=default<u32[:]>(),
values:blot_check_numeric_proof_terms::Kind[:]=default<blot_check_numeric_proof_terms::Kind[:]>(),
operands:blot_check_numeric_proof_terms::Term[:]=default<blot_check_numeric_proof_terms::Term[:]>(),
requirements:blot_check_numeric_proof_contracts::Requirement[:]=default<blot_check_numeric_proof_contracts::Requirement[:]>(),
parameters:u32[:]=default<u32[:]>(),
}
struct CheckedOwnerState {generation:u64=0,live:bool=false,headers:CheckedHeaderLease[:]=default<CheckedHeaderLease[:]>(),
function_exit_lambdas:blot_parse_ast::Id[:]=default<blot_parse_ast::Id[:]>(),
usage_loans:UsageLoan[:]=default<UsageLoan[:]>(),
proof_contracts:ProofContract[:]=default<ProofContract[:]>(),
rank_implementations:RankImplementation[:]=default<RankImplementation[:]>(),
generative_bindings:blot_check_generative_schemes::Binder[:]=default<blot_check_generative_schemes::Binder[:]>(),
dictionary_selections:DictionarySelection[:]=default<DictionarySelection[:]>(),
dictionary_uses:DictionaryUse[:]=default<DictionaryUse[:]>(),
iterator_bodies:blot_parse_ast::Id[:]=default<blot_parse_ast::Id[:]>(),
computations:Computation[:]=default<Computation[:]>(),
request_loops:RequestLoop[:]=default<RequestLoop[:]>(),
request_arms:RequestArm[:]=default<RequestArm[:]>(),
request_controls:RequestControl[:]=default<RequestControl[:]>(),
reflections:Reflection[:]=default<Reflection[:]>(),
tag_origins:TagOrigin[:]=default<TagOrigin[:]>(),
effect_scopes:EffectScope[:]=default<EffectScope[:]>(),
effect_scope_ids:u32[:]=default<u32[:]>(),
effect_runners:EffectRunner[:]=default<EffectRunner[:]>(),
effect_runner_ids:u32[:]=default<u32[:]>(),
provider_blocks:ProviderBlock[:]=default<ProviderBlock[:]>(),
provider_block_ids:u32[:]=default<u32[:]>(),
body_closed_rows:ClosedRow[:]=default<ClosedRow[:]>(),
lambda_closed_rows:blot_check_types::List[:]=default<blot_check_types::List[:]>(),
dispatch_signatures:blot_check_types::Id[:]=default<blot_check_types::Id[:]>(),
covered_requirements:CoveredRequirement[:]=default<CoveredRequirement[:]>(),
effect_families:EffectFamily[:]=default<EffectFamily[:]>(),
effect_templates:EffectTemplate[:]=default<EffectTemplate[:]>(),
operation_uses:OperationUse[:]=default<OperationUse[:]>(),
operation_refs:u32[:]=default<u32[:]>(),
expr_types:blot_check_types::Id[:]=default<blot_check_types::Id[:]>(),
resolved:BindingId[:]=default<BindingId[:]>(),
bindings:Binding[:]=default<Binding[:]>(),
merges:Merge[:]=default<Merge[:]>(),
obligations:blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),
diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),
associated:Associated[:]=default<Associated[:]>(),
nominals:Nominal[:]=default<Nominal[:]>(),
contracts:Contract[:]=default<Contract[:]>(),
contract_predicates:blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),
contract_members:ContractMember[:]=default<ContractMember[:]>(),
implementations:Implementation[:]=default<Implementation[:]>(),
implementation_predicates:blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),
implementation_members:ImplementationMember[:]=default<ImplementationMember[:]>(),
member_templates:blot_reuse_principal_interface::MemberTemplate[:]=default<blot_reuse_principal_interface::MemberTemplate[:]>(),
selected_proofs:blot_reuse_principal_interface::SelectedProof[:]=default<blot_reuse_principal_interface::SelectedProof[:]>(),
selected_members:ImplementationMember[:]=default<ImplementationMember[:]>(),
selected_edges:u32[:]=default<u32[:]>(),
selected_uses:blot_reuse_principal_interface::SelectedUse[:]=default<blot_reuse_principal_interface::SelectedUse[:]>(),
constructors:Constructor[:]=default<Constructor[:]>(),
constructor_resolved:u32[:]=default<u32[:]>(),
projections:u32[:]=default<u32[:]>(),
access_paths:blot_check_types::List[:]=default<blot_check_types::List[:]>(),
access_nodes:blot_check_types::List[:]=default<blot_check_types::List[:]>(),
access_types:blot_check_types::List[:]=default<blot_check_types::List[:]>(),
projection_resolved:u32[:]=default<u32[:]>(),
projection_catalog:Projection[:]=default<Projection[:]>(),
rebindings:Rebinding[:]=default<Rebinding[:]>(),
resolver_blocks:ResolverBlock[:]=default<ResolverBlock[:]>(),
resolver_ops:ResolverOp[:]=default<ResolverOp[:]>(),
resolver_joins:ResolverJoin[:]=default<ResolverJoin[:]>(),
resolver_completions:ResolverCompletion[:]=default<ResolverCompletion[:]>(),
resolver_loops:ResolverLoop[:]=default<ResolverLoop[:]>(),
resolver_block_ids:u32[:]=default<u32[:]>(),
resolver_op_ids:u32[:]=default<u32[:]>(),
resolver_join_ids:u32[:]=default<u32[:]>(),
resolver_loop_ids:u32[:]=default<u32[:]>(),
loop_carries:LoopCarry[:]=default<LoopCarry[:]>(),
loop_ranges:blot_check_types::List[:]=default<blot_check_types::List[:]>(),
loop_exits:LoopExit[:]=default<LoopExit[:]>(),
statement_arms:StatementArm[:]=default<StatementArm[:]>(),
declarations:SourceDeclaration[:]=default<SourceDeclaration[:]>(),
cap_nodes:blot_check_capability_contracts::Term[:]=default<blot_check_capability_contracts::Term[:]>(),
cap_words:u32[:]=default<u32[:]>(),
cap_bindings:blot_check_capability_contracts::Binding[:]=default<blot_check_capability_contracts::Binding[:]>(),
body_debits:blot_check_numeric_proof_bodies::Debit[:]=default<blot_check_numeric_proof_bodies::Debit[:]>(),
body_operands:blot_check_numeric_proof_terms::Term[:]=default<blot_check_numeric_proof_terms::Term[:]>(),
body_introductions:blot_check_numeric_proof_bodies::Introduction[:]=default<blot_check_numeric_proof_bodies::Introduction[:]>(),
body_parameters:blot_check_numeric_proof_bodies::Parameter[:]=default<blot_check_numeric_proof_bodies::Parameter[:]>(),
body_uses:blot_check_numeric_proof_bodies::Use[:]=default<blot_check_numeric_proof_bodies::Use[:]>(),
editor_names:EditorName[:]=default<EditorName[:]>(),
}
reusable var checked_owners:CheckedOwnerState[>..]=[];
reusable[] var checked_headers:CheckedHeaderLease[>..];
reusable[] var checked_function_exit_lambdas:blot_parse_ast::Id[>..];
reusable[] var checked_usage_loans:UsageLoan[>..];
reusable[] var checked_proof_contracts:ProofContract[>..];
reusable[] var checked_rank_implementations:RankImplementation[>..];
reusable[] var checked_generative_bindings:blot_check_generative_schemes::Binder[>..];
reusable[] var checked_dictionary_selections:DictionarySelection[>..];
reusable[] var checked_dictionary_uses:DictionaryUse[>..];
reusable[] var checked_iterator_bodies:blot_parse_ast::Id[>..];
reusable[] var checked_computations:Computation[>..];
reusable[] var checked_request_loops:RequestLoop[>..];
reusable[] var checked_request_arms:RequestArm[>..];
reusable[] var checked_request_controls:RequestControl[>..];
reusable[] var checked_reflections:Reflection[>..];
reusable[] var checked_tag_origins:TagOrigin[>..];
reusable[] var checked_effect_scopes:EffectScope[>..];
reusable[] var checked_effect_scope_ids:u32[>..];
reusable[] var checked_effect_runners:EffectRunner[>..];
reusable[] var checked_effect_runner_ids:u32[>..];
reusable[] var checked_provider_blocks:ProviderBlock[>..];
reusable[] var checked_provider_block_ids:u32[>..];
reusable[] var checked_body_closed_rows:ClosedRow[>..];
reusable[] var checked_lambda_closed_rows:blot_check_types::List[>..];
reusable[] var checked_dispatch_signatures:blot_check_types::Id[>..];
reusable[] var checked_covered_requirements:CoveredRequirement[>..];
reusable[] var checked_effect_families:EffectFamily[>..];
reusable[] var checked_effect_templates:EffectTemplate[>..];
reusable[] var checked_operation_uses:OperationUse[>..];
reusable[] var checked_operation_refs:u32[>..];
reusable[] var checked_expr_types:blot_check_types::Id[>..];
reusable[] var checked_resolved:BindingId[>..];
reusable[] var checked_bindings:Binding[>..];
reusable[] var checked_merges:Merge[>..];
reusable[] var checked_obligations:blot_check_types::Obligation[>..];
reusable[] var checked_diagnostics:Diagnostic[>..];
reusable[] var checked_associated:Associated[>..];
reusable[] var checked_nominals:Nominal[>..];
reusable[] var checked_contracts:Contract[>..];
reusable[] var checked_contract_predicates:blot_check_types::Obligation[>..];
reusable[] var checked_contract_members:ContractMember[>..];
reusable[] var checked_implementations:Implementation[>..];
reusable[] var checked_implementation_predicates:blot_check_types::Obligation[>..];
reusable[] var checked_implementation_members:ImplementationMember[>..];
reusable[] var checked_member_templates:blot_reuse_principal_interface::MemberTemplate[>..];
reusable[] var checked_selected_proofs:blot_reuse_principal_interface::SelectedProof[>..];
reusable[] var checked_selected_members:ImplementationMember[>..];
reusable[] var checked_selected_edges:u32[>..];
reusable[] var checked_selected_uses:blot_reuse_principal_interface::SelectedUse[>..];
reusable[] var checked_constructors:Constructor[>..];
reusable[] var checked_constructor_resolved:u32[>..];
reusable[] var checked_projections:u32[>..];
reusable[] var checked_access_paths:blot_check_types::List[>..];
reusable[] var checked_access_nodes:blot_check_types::List[>..];
reusable[] var checked_access_types:blot_check_types::List[>..];
reusable[] var checked_projection_resolved:u32[>..];
reusable[] var checked_projection_catalog:Projection[>..];
reusable[] var checked_rebindings:Rebinding[>..];
reusable[] var checked_resolver_blocks:ResolverBlock[>..];
reusable[] var checked_resolver_ops:ResolverOp[>..];
reusable[] var checked_resolver_joins:ResolverJoin[>..];
reusable[] var checked_resolver_completions:ResolverCompletion[>..];
reusable[] var checked_resolver_loops:ResolverLoop[>..];
reusable[] var checked_resolver_block_ids:u32[>..];
reusable[] var checked_resolver_op_ids:u32[>..];
reusable[] var checked_resolver_join_ids:u32[>..];
reusable[] var checked_resolver_loop_ids:u32[>..];
reusable[] var checked_loop_carries:LoopCarry[>..];
reusable[] var checked_loop_ranges:blot_check_types::List[>..];
reusable[] var checked_loop_exits:LoopExit[>..];
reusable[] var checked_statement_arms:StatementArm[>..];
reusable[] var checked_declarations:SourceDeclaration[>..];
reusable[] var checked_cap_nodes:blot_check_capability_contracts::Term[>..];
reusable[] var checked_cap_words:u32[>..];
reusable[] var checked_cap_bindings:blot_check_capability_contracts::Binding[>..];
reusable[] var checked_body_debits:blot_check_numeric_proof_bodies::Debit[>..];
reusable[] var checked_body_operands:blot_check_numeric_proof_terms::Term[>..];
reusable[] var checked_body_introductions:blot_check_numeric_proof_bodies::Introduction[>..];
reusable[] var checked_body_parameters:blot_check_numeric_proof_bodies::Parameter[>..];
reusable[] var checked_body_uses:blot_check_numeric_proof_bodies::Use[>..];
reusable[] var checked_editor_names:EditorName[>..];
reusable[] var checked_header_value_slots:u32[>..];
reusable[] var checked_header_proof_slots:u32[>..];
reusable[] var checked_header_values:blot_check_numeric_proof_terms::Kind[>..];
reusable[] var checked_header_operands:blot_check_numeric_proof_terms::Term[>..];
reusable[] var checked_header_requirements:blot_check_numeric_proof_contracts::Requirement[>..];
reusable[] var checked_header_parameters:u32[>..];
fn valid(self_:CheckedOwner)->bool {return self_.lease!=0 && self_.lease-1<checked_owners.len && checked_owners[self_.lease-1].live && checked_owners[self_.lease-1].generation==self_.generation;}
fn checkedOwnerState(self_:CheckedOwner)->CheckedOwnerState& {assert(self_.valid());return checked_owners[self_.lease-1];}
fn newCheckedOwner()->CheckedOwner,blot_error::Error {if checked_owners.len>=0xffffffff {return CheckedOwner{..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let index=checked_owners.alloc_index(CheckedOwnerState{generation:generation,live:true, ..});return CheckedOwner{(index+1) as u32,generation, ..},blot_error::Error.none;}
fn ownChecked_function_exit_lambdas(owner:CheckedOwner,values:const blot_parse_ast::Id[:])->blot_parse_ast::Id[:] {let state .= checkedOwnerState(owner);assert(state.function_exit_lambdas.len==0);let result=checked_function_exit_lambdas.alloc_slice(values.len);for value,index in values {result[index]=value;}state.function_exit_lambdas=result;return result;}
fn ownChecked_usage_loans(owner:CheckedOwner,values:const UsageLoan[:])->UsageLoan[:] {let state .= checkedOwnerState(owner);assert(state.usage_loans.len==0);let result=checked_usage_loans.alloc_slice(values.len);for value,index in values {result[index]=value;}state.usage_loans=result;return result;}
fn ownChecked_proof_contracts(owner:CheckedOwner,values:const ProofContract[:])->ProofContract[:] {let state .= checkedOwnerState(owner);assert(state.proof_contracts.len==0);let result=checked_proof_contracts.alloc_slice(values.len);for value,index in values {result[index]=value;}state.proof_contracts=result;return result;}
fn ownChecked_rank_implementations(owner:CheckedOwner,values:const RankImplementation[:])->RankImplementation[:] {let state .= checkedOwnerState(owner);assert(state.rank_implementations.len==0);let result=checked_rank_implementations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.rank_implementations=result;return result;}
fn ownChecked_generative_bindings(owner:CheckedOwner,values:const blot_check_generative_schemes::Binder[:])->blot_check_generative_schemes::Binder[:] {let state .= checkedOwnerState(owner);assert(state.generative_bindings.len==0);let result=checked_generative_bindings.alloc_slice(values.len);for value,index in values {result[index]=value;}state.generative_bindings=result;return result;}
fn ownChecked_dictionary_selections(owner:CheckedOwner,values:const DictionarySelection[:])->DictionarySelection[:] {let state .= checkedOwnerState(owner);assert(state.dictionary_selections.len==0);let result=checked_dictionary_selections.alloc_slice(values.len);for value,index in values {result[index]=value;}state.dictionary_selections=result;return result;}
fn ownChecked_dictionary_uses(owner:CheckedOwner,values:const DictionaryUse[:])->DictionaryUse[:] {let state .= checkedOwnerState(owner);assert(state.dictionary_uses.len==0);let result=checked_dictionary_uses.alloc_slice(values.len);for value,index in values {result[index]=value;}state.dictionary_uses=result;return result;}
fn ownChecked_iterator_bodies(owner:CheckedOwner,values:const blot_parse_ast::Id[:])->blot_parse_ast::Id[:] {let state .= checkedOwnerState(owner);assert(state.iterator_bodies.len==0);let result=checked_iterator_bodies.alloc_slice(values.len);for value,index in values {result[index]=value;}state.iterator_bodies=result;return result;}
fn ownChecked_computations(owner:CheckedOwner,values:const Computation[:])->Computation[:] {let state .= checkedOwnerState(owner);assert(state.computations.len==0);let result=checked_computations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.computations=result;return result;}
fn ownChecked_request_loops(owner:CheckedOwner,values:const RequestLoop[:])->RequestLoop[:] {let state .= checkedOwnerState(owner);assert(state.request_loops.len==0);let result=checked_request_loops.alloc_slice(values.len);for value,index in values {result[index]=value;}state.request_loops=result;return result;}
fn ownChecked_request_arms(owner:CheckedOwner,values:const RequestArm[:])->RequestArm[:] {let state .= checkedOwnerState(owner);assert(state.request_arms.len==0);let result=checked_request_arms.alloc_slice(values.len);for value,index in values {result[index]=value;}state.request_arms=result;return result;}
fn ownChecked_request_controls(owner:CheckedOwner,values:const RequestControl[:])->RequestControl[:] {let state .= checkedOwnerState(owner);assert(state.request_controls.len==0);let result=checked_request_controls.alloc_slice(values.len);for value,index in values {result[index]=value;}state.request_controls=result;return result;}
fn ownChecked_reflections(owner:CheckedOwner,values:const Reflection[:])->Reflection[:] {let state .= checkedOwnerState(owner);assert(state.reflections.len==0);let result=checked_reflections.alloc_slice(values.len);for value,index in values {result[index]=value;}state.reflections=result;return result;}
fn ownChecked_tag_origins(owner:CheckedOwner,values:const TagOrigin[:])->TagOrigin[:] {let state .= checkedOwnerState(owner);assert(state.tag_origins.len==0);let result=checked_tag_origins.alloc_slice(values.len);for value,index in values {result[index]=value;}state.tag_origins=result;return result;}
fn ownChecked_effect_scopes(owner:CheckedOwner,values:const EffectScope[:])->EffectScope[:] {let state .= checkedOwnerState(owner);assert(state.effect_scopes.len==0);let result=checked_effect_scopes.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_scopes=result;return result;}
fn ownChecked_effect_scope_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.effect_scope_ids.len==0);let result=checked_effect_scope_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_scope_ids=result;return result;}
fn ownChecked_effect_runners(owner:CheckedOwner,values:const EffectRunner[:])->EffectRunner[:] {let state .= checkedOwnerState(owner);assert(state.effect_runners.len==0);let result=checked_effect_runners.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_runners=result;return result;}
fn ownChecked_effect_runner_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.effect_runner_ids.len==0);let result=checked_effect_runner_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_runner_ids=result;return result;}
fn ownChecked_provider_blocks(owner:CheckedOwner,values:const ProviderBlock[:])->ProviderBlock[:] {let state .= checkedOwnerState(owner);assert(state.provider_blocks.len==0);let result=checked_provider_blocks.alloc_slice(values.len);for value,index in values {result[index]=value;}state.provider_blocks=result;return result;}
fn ownChecked_provider_block_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.provider_block_ids.len==0);let result=checked_provider_block_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.provider_block_ids=result;return result;}
fn ownChecked_body_closed_rows(owner:CheckedOwner,values:const ClosedRow[:])->ClosedRow[:] {let state .= checkedOwnerState(owner);assert(state.body_closed_rows.len==0);let result=checked_body_closed_rows.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_closed_rows=result;return result;}
fn ownChecked_lambda_closed_rows(owner:CheckedOwner,values:const blot_check_types::List[:])->blot_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.lambda_closed_rows.len==0);let result=checked_lambda_closed_rows.alloc_slice(values.len);for value,index in values {result[index]=value;}state.lambda_closed_rows=result;return result;}
fn ownChecked_dispatch_signatures(owner:CheckedOwner,values:const blot_check_types::Id[:])->blot_check_types::Id[:] {let state .= checkedOwnerState(owner);assert(state.dispatch_signatures.len==0);let result=checked_dispatch_signatures.alloc_slice(values.len);for value,index in values {result[index]=value;}state.dispatch_signatures=result;return result;}
fn ownChecked_covered_requirements(owner:CheckedOwner,values:const CoveredRequirement[:])->CoveredRequirement[:] {let state .= checkedOwnerState(owner);assert(state.covered_requirements.len==0);let result=checked_covered_requirements.alloc_slice(values.len);for value,index in values {result[index]=value;}state.covered_requirements=result;return result;}
fn ownChecked_effect_families(owner:CheckedOwner,values:const EffectFamily[:])->EffectFamily[:] {let state .= checkedOwnerState(owner);assert(state.effect_families.len==0);let result=checked_effect_families.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_families=result;return result;}
fn ownChecked_effect_templates(owner:CheckedOwner,values:const EffectTemplate[:])->EffectTemplate[:] {let state .= checkedOwnerState(owner);assert(state.effect_templates.len==0);let result=checked_effect_templates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_templates=result;return result;}
fn ownChecked_operation_uses(owner:CheckedOwner,values:const OperationUse[:])->OperationUse[:] {let state .= checkedOwnerState(owner);assert(state.operation_uses.len==0);let result=checked_operation_uses.alloc_slice(values.len);for value,index in values {result[index]=value;}state.operation_uses=result;return result;}
fn ownChecked_operation_refs(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.operation_refs.len==0);let result=checked_operation_refs.alloc_slice(values.len);for value,index in values {result[index]=value;}state.operation_refs=result;return result;}
fn ownChecked_expr_types(owner:CheckedOwner,values:const blot_check_types::Id[:])->blot_check_types::Id[:] {let state .= checkedOwnerState(owner);assert(state.expr_types.len==0);let result=checked_expr_types.alloc_slice(values.len);for value,index in values {result[index]=value;}state.expr_types=result;return result;}
fn ownChecked_resolved(owner:CheckedOwner,values:const BindingId[:])->BindingId[:] {let state .= checkedOwnerState(owner);assert(state.resolved.len==0);let result=checked_resolved.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolved=result;return result;}
fn ownChecked_bindings(owner:CheckedOwner,values:const Binding[:])->Binding[:] {let state .= checkedOwnerState(owner);assert(state.bindings.len==0);let result=checked_bindings.alloc_slice(values.len);for value,index in values {result[index]=value;}state.bindings=result;return result;}
fn ownChecked_merges(owner:CheckedOwner,values:const Merge[:])->Merge[:] {let state .= checkedOwnerState(owner);assert(state.merges.len==0);let result=checked_merges.alloc_slice(values.len);for value,index in values {result[index]=value;}state.merges=result;return result;}
fn ownChecked_obligations(owner:CheckedOwner,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {let state .= checkedOwnerState(owner);assert(state.obligations.len==0);let result=checked_obligations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.obligations=result;return result;}
fn ownChecked_diagnostics(owner:CheckedOwner,values:const Diagnostic[:])->Diagnostic[:] {let state .= checkedOwnerState(owner);assert(state.diagnostics.len==0);let result=checked_diagnostics.alloc_slice(values.len);for value,index in values {result[index]=value;}state.diagnostics=result;return result;}
fn ownChecked_associated(owner:CheckedOwner,values:const Associated[:])->Associated[:] {let state .= checkedOwnerState(owner);assert(state.associated.len==0);let result=checked_associated.alloc_slice(values.len);for value,index in values {result[index]=value;}state.associated=result;return result;}
fn ownChecked_nominals(owner:CheckedOwner,values:const Nominal[:])->Nominal[:] {let state .= checkedOwnerState(owner);assert(state.nominals.len==0);let result=checked_nominals.alloc_slice(values.len);for value,index in values {result[index]=value;}state.nominals=result;return result;}
fn ownChecked_contracts(owner:CheckedOwner,values:const Contract[:])->Contract[:] {let state .= checkedOwnerState(owner);assert(state.contracts.len==0);let result=checked_contracts.alloc_slice(values.len);for value,index in values {result[index]=value;}state.contracts=result;return result;}
fn ownChecked_contract_predicates(owner:CheckedOwner,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {let state .= checkedOwnerState(owner);assert(state.contract_predicates.len==0);let result=checked_contract_predicates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.contract_predicates=result;return result;}
fn ownChecked_contract_members(owner:CheckedOwner,values:const ContractMember[:])->ContractMember[:] {let state .= checkedOwnerState(owner);assert(state.contract_members.len==0);let result=checked_contract_members.alloc_slice(values.len);for value,index in values {result[index]=value;}state.contract_members=result;return result;}
fn ownChecked_implementations(owner:CheckedOwner,values:const Implementation[:])->Implementation[:] {let state .= checkedOwnerState(owner);assert(state.implementations.len==0);let result=checked_implementations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.implementations=result;return result;}
fn ownChecked_implementation_predicates(owner:CheckedOwner,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {let state .= checkedOwnerState(owner);assert(state.implementation_predicates.len==0);let result=checked_implementation_predicates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.implementation_predicates=result;return result;}
fn ownChecked_implementation_members(owner:CheckedOwner,values:const ImplementationMember[:])->ImplementationMember[:] {let state .= checkedOwnerState(owner);assert(state.implementation_members.len==0);let result=checked_implementation_members.alloc_slice(values.len);for value,index in values {result[index]=value;}state.implementation_members=result;return result;}
fn ownChecked_member_templates(owner:CheckedOwner,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:] {let state .= checkedOwnerState(owner);assert(state.member_templates.len==0);let result=checked_member_templates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.member_templates=result;return result;}
fn ownChecked_selected_proofs(owner:CheckedOwner,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:] {let state .= checkedOwnerState(owner);assert(state.selected_proofs.len==0);let result=checked_selected_proofs.alloc_slice(values.len);for value,index in values {result[index]=value;}state.selected_proofs=result;return result;}
fn ownChecked_selected_members(owner:CheckedOwner,values:const ImplementationMember[:])->ImplementationMember[:] {let state .= checkedOwnerState(owner);assert(state.selected_members.len==0);let result=checked_selected_members.alloc_slice(values.len);for value,index in values {result[index]=value;}state.selected_members=result;return result;}
fn ownChecked_selected_edges(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.selected_edges.len==0);let result=checked_selected_edges.alloc_slice(values.len);for value,index in values {result[index]=value;}state.selected_edges=result;return result;}
fn ownChecked_selected_uses(owner:CheckedOwner,values:const blot_reuse_principal_interface::SelectedUse[:])->blot_reuse_principal_interface::SelectedUse[:] {let state .= checkedOwnerState(owner);assert(state.selected_uses.len==0);let result=checked_selected_uses.alloc_slice(values.len);for value,index in values {result[index]=value;}state.selected_uses=result;return result;}
fn ownChecked_constructors(owner:CheckedOwner,values:const Constructor[:])->Constructor[:] {let state .= checkedOwnerState(owner);assert(state.constructors.len==0);let result=checked_constructors.alloc_slice(values.len);for value,index in values {result[index]=value;}state.constructors=result;return result;}
fn ownChecked_constructor_resolved(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.constructor_resolved.len==0);let result=checked_constructor_resolved.alloc_slice(values.len);for value,index in values {result[index]=value;}state.constructor_resolved=result;return result;}
fn ownChecked_projections(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.projections.len==0);let result=checked_projections.alloc_slice(values.len);for value,index in values {result[index]=value;}state.projections=result;return result;}
fn ownChecked_access_paths(owner:CheckedOwner,values:const blot_check_types::List[:])->blot_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.access_paths.len==0);let result=checked_access_paths.alloc_slice(values.len);for value,index in values {result[index]=value;}state.access_paths=result;return result;}
fn ownChecked_access_nodes(owner:CheckedOwner,values:const blot_check_types::List[:])->blot_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.access_nodes.len==0);let result=checked_access_nodes.alloc_slice(values.len);for value,index in values {result[index]=value;}state.access_nodes=result;return result;}
fn ownChecked_access_types(owner:CheckedOwner,values:const blot_check_types::List[:])->blot_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.access_types.len==0);let result=checked_access_types.alloc_slice(values.len);for value,index in values {result[index]=value;}state.access_types=result;return result;}
fn ownChecked_projection_resolved(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.projection_resolved.len==0);let result=checked_projection_resolved.alloc_slice(values.len);for value,index in values {result[index]=value;}state.projection_resolved=result;return result;}
fn ownChecked_projection_catalog(owner:CheckedOwner,values:const Projection[:])->Projection[:] {let state .= checkedOwnerState(owner);assert(state.projection_catalog.len==0);let result=checked_projection_catalog.alloc_slice(values.len);for value,index in values {result[index]=value;}state.projection_catalog=result;return result;}
fn ownChecked_rebindings(owner:CheckedOwner,values:const Rebinding[:])->Rebinding[:] {let state .= checkedOwnerState(owner);assert(state.rebindings.len==0);let result=checked_rebindings.alloc_slice(values.len);for value,index in values {result[index]=value;}state.rebindings=result;return result;}
fn ownChecked_resolver_blocks(owner:CheckedOwner,values:const ResolverBlock[:])->ResolverBlock[:] {let state .= checkedOwnerState(owner);assert(state.resolver_blocks.len==0);let result=checked_resolver_blocks.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_blocks=result;return result;}
fn ownChecked_resolver_ops(owner:CheckedOwner,values:const ResolverOp[:])->ResolverOp[:] {let state .= checkedOwnerState(owner);assert(state.resolver_ops.len==0);let result=checked_resolver_ops.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_ops=result;return result;}
fn ownChecked_resolver_joins(owner:CheckedOwner,values:const ResolverJoin[:])->ResolverJoin[:] {let state .= checkedOwnerState(owner);assert(state.resolver_joins.len==0);let result=checked_resolver_joins.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_joins=result;return result;}
fn ownChecked_resolver_completions(owner:CheckedOwner,values:const ResolverCompletion[:])->ResolverCompletion[:] {let state .= checkedOwnerState(owner);assert(state.resolver_completions.len==0);let result=checked_resolver_completions.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_completions=result;return result;}
fn ownChecked_resolver_loops(owner:CheckedOwner,values:const ResolverLoop[:])->ResolverLoop[:] {let state .= checkedOwnerState(owner);assert(state.resolver_loops.len==0);let result=checked_resolver_loops.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_loops=result;return result;}
fn ownChecked_resolver_block_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.resolver_block_ids.len==0);let result=checked_resolver_block_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_block_ids=result;return result;}
fn ownChecked_resolver_op_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.resolver_op_ids.len==0);let result=checked_resolver_op_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_op_ids=result;return result;}
fn ownChecked_resolver_join_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.resolver_join_ids.len==0);let result=checked_resolver_join_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_join_ids=result;return result;}
fn ownChecked_resolver_loop_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.resolver_loop_ids.len==0);let result=checked_resolver_loop_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolver_loop_ids=result;return result;}
fn ownChecked_loop_carries(owner:CheckedOwner,values:const LoopCarry[:])->LoopCarry[:] {let state .= checkedOwnerState(owner);assert(state.loop_carries.len==0);let result=checked_loop_carries.alloc_slice(values.len);for value,index in values {result[index]=value;}state.loop_carries=result;return result;}
fn ownChecked_loop_ranges(owner:CheckedOwner,values:const blot_check_types::List[:])->blot_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.loop_ranges.len==0);let result=checked_loop_ranges.alloc_slice(values.len);for value,index in values {result[index]=value;}state.loop_ranges=result;return result;}
fn ownChecked_loop_exits(owner:CheckedOwner,values:const LoopExit[:])->LoopExit[:] {let state .= checkedOwnerState(owner);assert(state.loop_exits.len==0);let result=checked_loop_exits.alloc_slice(values.len);for value,index in values {result[index]=value;}state.loop_exits=result;return result;}
fn ownChecked_statement_arms(owner:CheckedOwner,values:const StatementArm[:])->StatementArm[:] {let state .= checkedOwnerState(owner);assert(state.statement_arms.len==0);let result=checked_statement_arms.alloc_slice(values.len);for value,index in values {result[index]=value;}state.statement_arms=result;return result;}
fn ownChecked_declarations(owner:CheckedOwner,values:const SourceDeclaration[:])->SourceDeclaration[:] {let state .= checkedOwnerState(owner);assert(state.declarations.len==0);let result=checked_declarations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.declarations=result;return result;}
fn ownChecked_cap_nodes(owner:CheckedOwner,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:] {let state .= checkedOwnerState(owner);assert(state.cap_nodes.len==0);let result=checked_cap_nodes.alloc_slice(values.len);for value,index in values {result[index]=value;}state.cap_nodes=result;return result;}
fn ownChecked_cap_words(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.cap_words.len==0);let result=checked_cap_words.alloc_slice(values.len);for value,index in values {result[index]=value;}state.cap_words=result;return result;}
fn ownChecked_cap_bindings(owner:CheckedOwner,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:] {let state .= checkedOwnerState(owner);assert(state.cap_bindings.len==0);let result=checked_cap_bindings.alloc_slice(values.len);for value,index in values {result[index]=value;}state.cap_bindings=result;return result;}
fn ownChecked_body_debits(owner:CheckedOwner,values:const blot_check_numeric_proof_bodies::Debit[:])->blot_check_numeric_proof_bodies::Debit[:] {let state .= checkedOwnerState(owner);assert(state.body_debits.len==0);let result=checked_body_debits.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_debits=result;return result;}
fn ownChecked_body_operands(owner:CheckedOwner,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:] {let state .= checkedOwnerState(owner);assert(state.body_operands.len==0);let result=checked_body_operands.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_operands=result;return result;}
fn ownChecked_body_introductions(owner:CheckedOwner,values:const blot_check_numeric_proof_bodies::Introduction[:])->blot_check_numeric_proof_bodies::Introduction[:] {let state .= checkedOwnerState(owner);assert(state.body_introductions.len==0);let result=checked_body_introductions.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_introductions=result;return result;}
fn ownChecked_body_parameters(owner:CheckedOwner,values:const blot_check_numeric_proof_bodies::Parameter[:])->blot_check_numeric_proof_bodies::Parameter[:] {let state .= checkedOwnerState(owner);assert(state.body_parameters.len==0);let result=checked_body_parameters.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_parameters=result;return result;}
fn ownChecked_body_uses(owner:CheckedOwner,values:const blot_check_numeric_proof_bodies::Use[:])->blot_check_numeric_proof_bodies::Use[:] {let state .= checkedOwnerState(owner);assert(state.body_uses.len==0);let result=checked_body_uses.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_uses=result;return result;}
fn ownChecked_editor_names(owner:CheckedOwner,values:const EditorName[:])->EditorName[:] {let state .= checkedOwnerState(owner);assert(state.editor_names.len==0);let result=checked_editor_names.alloc_slice(values.len);for value,index in values {result[index]=value;}state.editor_names=result;return result;}
fn releaseCheckedHeader(header:CheckedHeaderLease&) {
if header.value_slots.len!=0 {checked_header_value_slots.free_slice(header.value_slots);header.value_slots=[];}
if header.proof_slots.len!=0 {checked_header_proof_slots.free_slice(header.proof_slots);header.proof_slots=[];}
if header.values.len!=0 {checked_header_values.free_slice(header.values);header.values=[];}
if header.operands.len!=0 {checked_header_operands.free_slice(header.operands);header.operands=[];}
if header.requirements.len!=0 {checked_header_requirements.free_slice(header.requirements);header.requirements=[];}
if header.parameters.len!=0 {checked_header_parameters.free_slice(header.parameters);header.parameters=[];}
}
fn ownCheckedHeaders(owner:CheckedOwner,contracts:ProofContract[:]) {let state .= checkedOwnerState(owner);state.headers=checked_headers.alloc_slice(contracts.len);for &contract,index in contracts {var lease=CheckedHeaderLease{..};
lease.value_slots=checked_header_value_slots.alloc_slice(contract.header.value_slots.len);for value,slot in contract.header.value_slots {lease.value_slots[slot]=value;}contract.header.value_slots=lease.value_slots;
lease.proof_slots=checked_header_proof_slots.alloc_slice(contract.header.proof_slots.len);for value,slot in contract.header.proof_slots {lease.proof_slots[slot]=value;}contract.header.proof_slots=lease.proof_slots;
lease.values=checked_header_values.alloc_slice(contract.header.values.len);for value,slot in contract.header.values {lease.values[slot]=value;}contract.header.values=lease.values;
lease.operands=checked_header_operands.alloc_slice(contract.header.operands.len);for value,slot in contract.header.operands {lease.operands[slot]=value;}contract.header.operands=lease.operands;
lease.requirements=checked_header_requirements.alloc_slice(contract.header.requirements.len);for value,slot in contract.header.requirements {lease.requirements[slot]=value;}contract.header.requirements=lease.requirements;
lease.parameters=checked_header_parameters.alloc_slice(contract.parameters.len);for value,slot in contract.parameters {lease.parameters[slot]=value;}contract.parameters=lease.parameters;
state.headers[index]=lease;}}
fn releaseCheckedBodies(owner:CheckedOwner) {let state .= checkedOwnerState(owner);
if state.function_exit_lambdas.len!=0 {checked_function_exit_lambdas.free_slice(state.function_exit_lambdas);state.function_exit_lambdas=default<blot_parse_ast::Id[:]>();}
if state.usage_loans.len!=0 {checked_usage_loans.free_slice(state.usage_loans);state.usage_loans=default<UsageLoan[:]>();}
if state.proof_contracts.len!=0 {checked_proof_contracts.free_slice(state.proof_contracts);state.proof_contracts=default<ProofContract[:]>();}
if state.rank_implementations.len!=0 {checked_rank_implementations.free_slice(state.rank_implementations);state.rank_implementations=default<RankImplementation[:]>();}
if state.generative_bindings.len!=0 {checked_generative_bindings.free_slice(state.generative_bindings);state.generative_bindings=default<blot_check_generative_schemes::Binder[:]>();}
if state.dictionary_selections.len!=0 {checked_dictionary_selections.free_slice(state.dictionary_selections);state.dictionary_selections=default<DictionarySelection[:]>();}
if state.dictionary_uses.len!=0 {checked_dictionary_uses.free_slice(state.dictionary_uses);state.dictionary_uses=default<DictionaryUse[:]>();}
if state.iterator_bodies.len!=0 {checked_iterator_bodies.free_slice(state.iterator_bodies);state.iterator_bodies=default<blot_parse_ast::Id[:]>();}
if state.computations.len!=0 {checked_computations.free_slice(state.computations);state.computations=default<Computation[:]>();}
if state.request_loops.len!=0 {checked_request_loops.free_slice(state.request_loops);state.request_loops=default<RequestLoop[:]>();}
if state.request_arms.len!=0 {checked_request_arms.free_slice(state.request_arms);state.request_arms=default<RequestArm[:]>();}
if state.request_controls.len!=0 {checked_request_controls.free_slice(state.request_controls);state.request_controls=default<RequestControl[:]>();}
if state.reflections.len!=0 {checked_reflections.free_slice(state.reflections);state.reflections=default<Reflection[:]>();}
if state.tag_origins.len!=0 {checked_tag_origins.free_slice(state.tag_origins);state.tag_origins=default<TagOrigin[:]>();}
if state.effect_scopes.len!=0 {checked_effect_scopes.free_slice(state.effect_scopes);state.effect_scopes=default<EffectScope[:]>();}
if state.effect_scope_ids.len!=0 {checked_effect_scope_ids.free_slice(state.effect_scope_ids);state.effect_scope_ids=default<u32[:]>();}
if state.effect_runners.len!=0 {checked_effect_runners.free_slice(state.effect_runners);state.effect_runners=default<EffectRunner[:]>();}
if state.effect_runner_ids.len!=0 {checked_effect_runner_ids.free_slice(state.effect_runner_ids);state.effect_runner_ids=default<u32[:]>();}
if state.provider_blocks.len!=0 {checked_provider_blocks.free_slice(state.provider_blocks);state.provider_blocks=default<ProviderBlock[:]>();}
if state.provider_block_ids.len!=0 {checked_provider_block_ids.free_slice(state.provider_block_ids);state.provider_block_ids=default<u32[:]>();}
if state.body_closed_rows.len!=0 {checked_body_closed_rows.free_slice(state.body_closed_rows);state.body_closed_rows=default<ClosedRow[:]>();}
if state.lambda_closed_rows.len!=0 {checked_lambda_closed_rows.free_slice(state.lambda_closed_rows);state.lambda_closed_rows=default<blot_check_types::List[:]>();}
if state.dispatch_signatures.len!=0 {checked_dispatch_signatures.free_slice(state.dispatch_signatures);state.dispatch_signatures=default<blot_check_types::Id[:]>();}
if state.covered_requirements.len!=0 {checked_covered_requirements.free_slice(state.covered_requirements);state.covered_requirements=default<CoveredRequirement[:]>();}
if state.operation_uses.len!=0 {checked_operation_uses.free_slice(state.operation_uses);state.operation_uses=default<OperationUse[:]>();}
if state.operation_refs.len!=0 {checked_operation_refs.free_slice(state.operation_refs);state.operation_refs=default<u32[:]>();}
if state.expr_types.len!=0 {checked_expr_types.free_slice(state.expr_types);state.expr_types=default<blot_check_types::Id[:]>();}
if state.bindings.len!=0 {checked_bindings.free_slice(state.bindings);state.bindings=default<Binding[:]>();}
if state.merges.len!=0 {checked_merges.free_slice(state.merges);state.merges=default<Merge[:]>();}
if state.obligations.len!=0 {checked_obligations.free_slice(state.obligations);state.obligations=default<blot_check_types::Obligation[:]>();}
if state.constructor_resolved.len!=0 {checked_constructor_resolved.free_slice(state.constructor_resolved);state.constructor_resolved=default<u32[:]>();}
if state.projections.len!=0 {checked_projections.free_slice(state.projections);state.projections=default<u32[:]>();}
if state.access_paths.len!=0 {checked_access_paths.free_slice(state.access_paths);state.access_paths=default<blot_check_types::List[:]>();}
if state.access_nodes.len!=0 {checked_access_nodes.free_slice(state.access_nodes);state.access_nodes=default<blot_check_types::List[:]>();}
if state.access_types.len!=0 {checked_access_types.free_slice(state.access_types);state.access_types=default<blot_check_types::List[:]>();}
if state.projection_resolved.len!=0 {checked_projection_resolved.free_slice(state.projection_resolved);state.projection_resolved=default<u32[:]>();}
if state.projection_catalog.len!=0 {checked_projection_catalog.free_slice(state.projection_catalog);state.projection_catalog=default<Projection[:]>();}
if state.rebindings.len!=0 {checked_rebindings.free_slice(state.rebindings);state.rebindings=default<Rebinding[:]>();}
if state.resolver_blocks.len!=0 {checked_resolver_blocks.free_slice(state.resolver_blocks);state.resolver_blocks=default<ResolverBlock[:]>();}
if state.resolver_ops.len!=0 {checked_resolver_ops.free_slice(state.resolver_ops);state.resolver_ops=default<ResolverOp[:]>();}
if state.resolver_joins.len!=0 {checked_resolver_joins.free_slice(state.resolver_joins);state.resolver_joins=default<ResolverJoin[:]>();}
if state.resolver_completions.len!=0 {checked_resolver_completions.free_slice(state.resolver_completions);state.resolver_completions=default<ResolverCompletion[:]>();}
if state.resolver_loops.len!=0 {checked_resolver_loops.free_slice(state.resolver_loops);state.resolver_loops=default<ResolverLoop[:]>();}
if state.resolver_block_ids.len!=0 {checked_resolver_block_ids.free_slice(state.resolver_block_ids);state.resolver_block_ids=default<u32[:]>();}
if state.resolver_op_ids.len!=0 {checked_resolver_op_ids.free_slice(state.resolver_op_ids);state.resolver_op_ids=default<u32[:]>();}
if state.resolver_join_ids.len!=0 {checked_resolver_join_ids.free_slice(state.resolver_join_ids);state.resolver_join_ids=default<u32[:]>();}
if state.resolver_loop_ids.len!=0 {checked_resolver_loop_ids.free_slice(state.resolver_loop_ids);state.resolver_loop_ids=default<u32[:]>();}
if state.loop_carries.len!=0 {checked_loop_carries.free_slice(state.loop_carries);state.loop_carries=default<LoopCarry[:]>();}
if state.loop_ranges.len!=0 {checked_loop_ranges.free_slice(state.loop_ranges);state.loop_ranges=default<blot_check_types::List[:]>();}
if state.loop_exits.len!=0 {checked_loop_exits.free_slice(state.loop_exits);state.loop_exits=default<LoopExit[:]>();}
if state.statement_arms.len!=0 {checked_statement_arms.free_slice(state.statement_arms);state.statement_arms=default<StatementArm[:]>();}
if state.cap_nodes.len!=0 {checked_cap_nodes.free_slice(state.cap_nodes);state.cap_nodes=default<blot_check_capability_contracts::Term[:]>();}
if state.cap_words.len!=0 {checked_cap_words.free_slice(state.cap_words);state.cap_words=default<u32[:]>();}
if state.cap_bindings.len!=0 {checked_cap_bindings.free_slice(state.cap_bindings);state.cap_bindings=default<blot_check_capability_contracts::Binding[:]>();}
if state.body_debits.len!=0 {checked_body_debits.free_slice(state.body_debits);state.body_debits=default<blot_check_numeric_proof_bodies::Debit[:]>();}
if state.body_operands.len!=0 {checked_body_operands.free_slice(state.body_operands);state.body_operands=default<blot_check_numeric_proof_terms::Term[:]>();}
if state.body_introductions.len!=0 {checked_body_introductions.free_slice(state.body_introductions);state.body_introductions=default<blot_check_numeric_proof_bodies::Introduction[:]>();}
if state.body_parameters.len!=0 {checked_body_parameters.free_slice(state.body_parameters);state.body_parameters=default<blot_check_numeric_proof_bodies::Parameter[:]>();}
if state.body_uses.len!=0 {checked_body_uses.free_slice(state.body_uses);state.body_uses=default<blot_check_numeric_proof_bodies::Use[:]>();}
if state.editor_names.len!=0 {checked_editor_names.free_slice(state.editor_names);state.editor_names=default<EditorName[:]>();}
for &header in state.headers {releaseCheckedHeader(header);}if state.headers.len!=0 {checked_headers.free_slice(state.headers);state.headers=default<CheckedHeaderLease[:]>();}
}
fn deinit(self_:CheckedOwner&) {if self_.lease==0 {return;}assert(self_.valid());let state .= checkedOwnerState(self_);
if state.function_exit_lambdas.len!=0 {checked_function_exit_lambdas.free_slice(state.function_exit_lambdas);state.function_exit_lambdas=default<blot_parse_ast::Id[:]>();}
if state.usage_loans.len!=0 {checked_usage_loans.free_slice(state.usage_loans);state.usage_loans=default<UsageLoan[:]>();}
if state.proof_contracts.len!=0 {checked_proof_contracts.free_slice(state.proof_contracts);state.proof_contracts=default<ProofContract[:]>();}
if state.rank_implementations.len!=0 {checked_rank_implementations.free_slice(state.rank_implementations);state.rank_implementations=default<RankImplementation[:]>();}
if state.generative_bindings.len!=0 {checked_generative_bindings.free_slice(state.generative_bindings);state.generative_bindings=default<blot_check_generative_schemes::Binder[:]>();}
if state.dictionary_selections.len!=0 {checked_dictionary_selections.free_slice(state.dictionary_selections);state.dictionary_selections=default<DictionarySelection[:]>();}
if state.dictionary_uses.len!=0 {checked_dictionary_uses.free_slice(state.dictionary_uses);state.dictionary_uses=default<DictionaryUse[:]>();}
if state.iterator_bodies.len!=0 {checked_iterator_bodies.free_slice(state.iterator_bodies);state.iterator_bodies=default<blot_parse_ast::Id[:]>();}
if state.computations.len!=0 {checked_computations.free_slice(state.computations);state.computations=default<Computation[:]>();}
if state.request_loops.len!=0 {checked_request_loops.free_slice(state.request_loops);state.request_loops=default<RequestLoop[:]>();}
if state.request_arms.len!=0 {checked_request_arms.free_slice(state.request_arms);state.request_arms=default<RequestArm[:]>();}
if state.request_controls.len!=0 {checked_request_controls.free_slice(state.request_controls);state.request_controls=default<RequestControl[:]>();}
if state.reflections.len!=0 {checked_reflections.free_slice(state.reflections);state.reflections=default<Reflection[:]>();}
if state.tag_origins.len!=0 {checked_tag_origins.free_slice(state.tag_origins);state.tag_origins=default<TagOrigin[:]>();}
if state.effect_scopes.len!=0 {checked_effect_scopes.free_slice(state.effect_scopes);state.effect_scopes=default<EffectScope[:]>();}
if state.effect_scope_ids.len!=0 {checked_effect_scope_ids.free_slice(state.effect_scope_ids);state.effect_scope_ids=default<u32[:]>();}
if state.effect_runners.len!=0 {checked_effect_runners.free_slice(state.effect_runners);state.effect_runners=default<EffectRunner[:]>();}
if state.effect_runner_ids.len!=0 {checked_effect_runner_ids.free_slice(state.effect_runner_ids);state.effect_runner_ids=default<u32[:]>();}
if state.provider_blocks.len!=0 {checked_provider_blocks.free_slice(state.provider_blocks);state.provider_blocks=default<ProviderBlock[:]>();}
if state.provider_block_ids.len!=0 {checked_provider_block_ids.free_slice(state.provider_block_ids);state.provider_block_ids=default<u32[:]>();}
if state.body_closed_rows.len!=0 {checked_body_closed_rows.free_slice(state.body_closed_rows);state.body_closed_rows=default<ClosedRow[:]>();}
if state.lambda_closed_rows.len!=0 {checked_lambda_closed_rows.free_slice(state.lambda_closed_rows);state.lambda_closed_rows=default<blot_check_types::List[:]>();}
if state.dispatch_signatures.len!=0 {checked_dispatch_signatures.free_slice(state.dispatch_signatures);state.dispatch_signatures=default<blot_check_types::Id[:]>();}
if state.covered_requirements.len!=0 {checked_covered_requirements.free_slice(state.covered_requirements);state.covered_requirements=default<CoveredRequirement[:]>();}
if state.effect_families.len!=0 {checked_effect_families.free_slice(state.effect_families);state.effect_families=default<EffectFamily[:]>();}
if state.effect_templates.len!=0 {checked_effect_templates.free_slice(state.effect_templates);state.effect_templates=default<EffectTemplate[:]>();}
if state.operation_uses.len!=0 {checked_operation_uses.free_slice(state.operation_uses);state.operation_uses=default<OperationUse[:]>();}
if state.operation_refs.len!=0 {checked_operation_refs.free_slice(state.operation_refs);state.operation_refs=default<u32[:]>();}
if state.expr_types.len!=0 {checked_expr_types.free_slice(state.expr_types);state.expr_types=default<blot_check_types::Id[:]>();}
if state.resolved.len!=0 {checked_resolved.free_slice(state.resolved);state.resolved=default<BindingId[:]>();}
if state.bindings.len!=0 {checked_bindings.free_slice(state.bindings);state.bindings=default<Binding[:]>();}
if state.merges.len!=0 {checked_merges.free_slice(state.merges);state.merges=default<Merge[:]>();}
if state.obligations.len!=0 {checked_obligations.free_slice(state.obligations);state.obligations=default<blot_check_types::Obligation[:]>();}
if state.diagnostics.len!=0 {checked_diagnostics.free_slice(state.diagnostics);state.diagnostics=default<Diagnostic[:]>();}
if state.associated.len!=0 {checked_associated.free_slice(state.associated);state.associated=default<Associated[:]>();}
if state.nominals.len!=0 {checked_nominals.free_slice(state.nominals);state.nominals=default<Nominal[:]>();}
if state.contracts.len!=0 {checked_contracts.free_slice(state.contracts);state.contracts=default<Contract[:]>();}
if state.contract_predicates.len!=0 {checked_contract_predicates.free_slice(state.contract_predicates);state.contract_predicates=default<blot_check_types::Obligation[:]>();}
if state.contract_members.len!=0 {checked_contract_members.free_slice(state.contract_members);state.contract_members=default<ContractMember[:]>();}
if state.implementations.len!=0 {checked_implementations.free_slice(state.implementations);state.implementations=default<Implementation[:]>();}
if state.implementation_predicates.len!=0 {checked_implementation_predicates.free_slice(state.implementation_predicates);state.implementation_predicates=default<blot_check_types::Obligation[:]>();}
if state.implementation_members.len!=0 {checked_implementation_members.free_slice(state.implementation_members);state.implementation_members=default<ImplementationMember[:]>();}
if state.member_templates.len!=0 {checked_member_templates.free_slice(state.member_templates);state.member_templates=default<blot_reuse_principal_interface::MemberTemplate[:]>();}
if state.selected_proofs.len!=0 {checked_selected_proofs.free_slice(state.selected_proofs);state.selected_proofs=default<blot_reuse_principal_interface::SelectedProof[:]>();}
if state.selected_members.len!=0 {checked_selected_members.free_slice(state.selected_members);state.selected_members=default<ImplementationMember[:]>();}
if state.selected_edges.len!=0 {checked_selected_edges.free_slice(state.selected_edges);state.selected_edges=default<u32[:]>();}
if state.selected_uses.len!=0 {checked_selected_uses.free_slice(state.selected_uses);state.selected_uses=default<blot_reuse_principal_interface::SelectedUse[:]>();}
if state.constructors.len!=0 {checked_constructors.free_slice(state.constructors);state.constructors=default<Constructor[:]>();}
if state.constructor_resolved.len!=0 {checked_constructor_resolved.free_slice(state.constructor_resolved);state.constructor_resolved=default<u32[:]>();}
if state.projections.len!=0 {checked_projections.free_slice(state.projections);state.projections=default<u32[:]>();}
if state.access_paths.len!=0 {checked_access_paths.free_slice(state.access_paths);state.access_paths=default<blot_check_types::List[:]>();}
if state.access_nodes.len!=0 {checked_access_nodes.free_slice(state.access_nodes);state.access_nodes=default<blot_check_types::List[:]>();}
if state.access_types.len!=0 {checked_access_types.free_slice(state.access_types);state.access_types=default<blot_check_types::List[:]>();}
if state.projection_resolved.len!=0 {checked_projection_resolved.free_slice(state.projection_resolved);state.projection_resolved=default<u32[:]>();}
if state.projection_catalog.len!=0 {checked_projection_catalog.free_slice(state.projection_catalog);state.projection_catalog=default<Projection[:]>();}
if state.rebindings.len!=0 {checked_rebindings.free_slice(state.rebindings);state.rebindings=default<Rebinding[:]>();}
if state.resolver_blocks.len!=0 {checked_resolver_blocks.free_slice(state.resolver_blocks);state.resolver_blocks=default<ResolverBlock[:]>();}
if state.resolver_ops.len!=0 {checked_resolver_ops.free_slice(state.resolver_ops);state.resolver_ops=default<ResolverOp[:]>();}
if state.resolver_joins.len!=0 {checked_resolver_joins.free_slice(state.resolver_joins);state.resolver_joins=default<ResolverJoin[:]>();}
if state.resolver_completions.len!=0 {checked_resolver_completions.free_slice(state.resolver_completions);state.resolver_completions=default<ResolverCompletion[:]>();}
if state.resolver_loops.len!=0 {checked_resolver_loops.free_slice(state.resolver_loops);state.resolver_loops=default<ResolverLoop[:]>();}
if state.resolver_block_ids.len!=0 {checked_resolver_block_ids.free_slice(state.resolver_block_ids);state.resolver_block_ids=default<u32[:]>();}
if state.resolver_op_ids.len!=0 {checked_resolver_op_ids.free_slice(state.resolver_op_ids);state.resolver_op_ids=default<u32[:]>();}
if state.resolver_join_ids.len!=0 {checked_resolver_join_ids.free_slice(state.resolver_join_ids);state.resolver_join_ids=default<u32[:]>();}
if state.resolver_loop_ids.len!=0 {checked_resolver_loop_ids.free_slice(state.resolver_loop_ids);state.resolver_loop_ids=default<u32[:]>();}
if state.loop_carries.len!=0 {checked_loop_carries.free_slice(state.loop_carries);state.loop_carries=default<LoopCarry[:]>();}
if state.loop_ranges.len!=0 {checked_loop_ranges.free_slice(state.loop_ranges);state.loop_ranges=default<blot_check_types::List[:]>();}
if state.loop_exits.len!=0 {checked_loop_exits.free_slice(state.loop_exits);state.loop_exits=default<LoopExit[:]>();}
if state.statement_arms.len!=0 {checked_statement_arms.free_slice(state.statement_arms);state.statement_arms=default<StatementArm[:]>();}
if state.declarations.len!=0 {checked_declarations.free_slice(state.declarations);state.declarations=default<SourceDeclaration[:]>();}
if state.cap_nodes.len!=0 {checked_cap_nodes.free_slice(state.cap_nodes);state.cap_nodes=default<blot_check_capability_contracts::Term[:]>();}
if state.cap_words.len!=0 {checked_cap_words.free_slice(state.cap_words);state.cap_words=default<u32[:]>();}
if state.cap_bindings.len!=0 {checked_cap_bindings.free_slice(state.cap_bindings);state.cap_bindings=default<blot_check_capability_contracts::Binding[:]>();}
if state.body_debits.len!=0 {checked_body_debits.free_slice(state.body_debits);state.body_debits=default<blot_check_numeric_proof_bodies::Debit[:]>();}
if state.body_operands.len!=0 {checked_body_operands.free_slice(state.body_operands);state.body_operands=default<blot_check_numeric_proof_terms::Term[:]>();}
if state.body_introductions.len!=0 {checked_body_introductions.free_slice(state.body_introductions);state.body_introductions=default<blot_check_numeric_proof_bodies::Introduction[:]>();}
if state.body_parameters.len!=0 {checked_body_parameters.free_slice(state.body_parameters);state.body_parameters=default<blot_check_numeric_proof_bodies::Parameter[:]>();}
if state.body_uses.len!=0 {checked_body_uses.free_slice(state.body_uses);state.body_uses=default<blot_check_numeric_proof_bodies::Use[:]>();}
if state.editor_names.len!=0 {checked_editor_names.free_slice(state.editor_names);state.editor_names=default<EditorName[:]>();}
for &header in state.headers {releaseCheckedHeader(header);}if state.headers.len!=0 {checked_headers.free_slice(state.headers);state.headers=default<CheckedHeaderLease[:]>();}let index=self_.lease-1;state.live=false;checked_owners.free(index);self_=CheckedOwner{..};}
fn deinit(self_:Checked&) {if !self_.owner.valid() {return;}deinitDiagnosticPayloads(self_.diagnostics);if self_.editor.present && self_.editor.value.context.present {self_.editor.value.context.value.deinit();}self_.types.deinit();self_.parameter_patterns.deinit();releaseCheckedPacket(self_.owner);self_.owner.deinit();self_=default<Checked>();}
fn deinit(self_:SourceValidation&) {if !self_.owner.valid() {return;}deinitDiagnosticPayloads(self_.diagnostics);self_.types.deinit();self_.parameter_patterns.deinit();self_.owner.deinit();self_=default<SourceValidation>();}
