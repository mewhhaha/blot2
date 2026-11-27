// Concrete retained checker output ownership. No borrowed factory tables escape.
namespace squid_check_check;
import check.types;
import parse.ast;
import reuse.principal_interface;
import support.error;
import support.native;

import std;
import .check;
import .check_packet_owner;
import .checked_views;
struct CheckedOwner {lease:u32=0,generation:u64=0}
struct CheckedOwnerState {generation:u64=0,live:bool=false,
function_exit_lambdas:squid_parse_ast::Id[:]=default<squid_parse_ast::Id[:]>(),
iterator_bodies:squid_parse_ast::Id[:]=default<squid_parse_ast::Id[:]>(),
computations:Computation[:]=default<Computation[:]>(),
reflections:Reflection[:]=default<Reflection[:]>(),
tag_origins:TagOrigin[:]=default<TagOrigin[:]>(),
effect_runners:EffectRunner[:]=default<EffectRunner[:]>(),
effect_runner_ids:u32[:]=default<u32[:]>(),
provider_blocks:ProviderBlock[:]=default<ProviderBlock[:]>(),
provider_block_ids:u32[:]=default<u32[:]>(),
body_closed_rows:ClosedRow[:]=default<ClosedRow[:]>(),
lambda_closed_rows:squid_check_types::List[:]=default<squid_check_types::List[:]>(),
dispatch_signatures:squid_check_types::Id[:]=default<squid_check_types::Id[:]>(),
covered_requirements:CoveredRequirement[:]=default<CoveredRequirement[:]>(),
effect_families:EffectFamily[:]=default<EffectFamily[:]>(),
effect_templates:EffectTemplate[:]=default<EffectTemplate[:]>(),
operation_uses:OperationUse[:]=default<OperationUse[:]>(),
operation_refs:u32[:]=default<u32[:]>(),
expr_types:squid_check_types::Id[:]=default<squid_check_types::Id[:]>(),
resolved:BindingId[:]=default<BindingId[:]>(),
bindings:Binding[:]=default<Binding[:]>(),
merges:Merge[:]=default<Merge[:]>(),
obligations:squid_check_types::Obligation[:]=default<squid_check_types::Obligation[:]>(),
diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),
associated:Associated[:]=default<Associated[:]>(),
nominals:Nominal[:]=default<Nominal[:]>(),
contracts:Contract[:]=default<Contract[:]>(),
contract_predicates:squid_check_types::Obligation[:]=default<squid_check_types::Obligation[:]>(),
contract_members:ContractMember[:]=default<ContractMember[:]>(),
implementations:Implementation[:]=default<Implementation[:]>(),
implementation_predicates:squid_check_types::Obligation[:]=default<squid_check_types::Obligation[:]>(),
implementation_members:ImplementationMember[:]=default<ImplementationMember[:]>(),
member_templates:squid_reuse_principal_interface::MemberTemplate[:]=default<squid_reuse_principal_interface::MemberTemplate[:]>(),
constructors:Constructor[:]=default<Constructor[:]>(),
constructor_resolved:u32[:]=default<u32[:]>(),
projections:u32[:]=default<u32[:]>(),
access_paths:squid_check_types::List[:]=default<squid_check_types::List[:]>(),
access_nodes:squid_check_types::List[:]=default<squid_check_types::List[:]>(),
access_types:squid_check_types::List[:]=default<squid_check_types::List[:]>(),
projection_resolved:u32[:]=default<u32[:]>(),
projection_catalog:Projection[:]=default<Projection[:]>(),
rebindings:Rebinding[:]=default<Rebinding[:]>(),
loop_carries:LoopCarry[:]=default<LoopCarry[:]>(),
loop_ranges:squid_check_types::List[:]=default<squid_check_types::List[:]>(),
loop_exits:LoopExit[:]=default<LoopExit[:]>(),
statement_arms:StatementArm[:]=default<StatementArm[:]>(),
declarations:SourceDeclaration[:]=default<SourceDeclaration[:]>(),
editor_names:EditorName[:]=default<EditorName[:]>(),
}
reusable var checked_owners:CheckedOwnerState[>..]=[];
reusable[] var checked_function_exit_lambdas:squid_parse_ast::Id[>..];
reusable[] var checked_iterator_bodies:squid_parse_ast::Id[>..];
reusable[] var checked_computations:Computation[>..];
reusable[] var checked_reflections:Reflection[>..];
reusable[] var checked_tag_origins:TagOrigin[>..];
reusable[] var checked_effect_runners:EffectRunner[>..];
reusable[] var checked_effect_runner_ids:u32[>..];
reusable[] var checked_provider_blocks:ProviderBlock[>..];
reusable[] var checked_provider_block_ids:u32[>..];
reusable[] var checked_body_closed_rows:ClosedRow[>..];
reusable[] var checked_lambda_closed_rows:squid_check_types::List[>..];
reusable[] var checked_dispatch_signatures:squid_check_types::Id[>..];
reusable[] var checked_covered_requirements:CoveredRequirement[>..];
reusable[] var checked_effect_families:EffectFamily[>..];
reusable[] var checked_effect_templates:EffectTemplate[>..];
reusable[] var checked_operation_uses:OperationUse[>..];
reusable[] var checked_operation_refs:u32[>..];
reusable[] var checked_expr_types:squid_check_types::Id[>..];
reusable[] var checked_resolved:BindingId[>..];
reusable[] var checked_bindings:Binding[>..];
reusable[] var checked_merges:Merge[>..];
reusable[] var checked_obligations:squid_check_types::Obligation[>..];
reusable[] var checked_diagnostics:Diagnostic[>..];
reusable[] var checked_associated:Associated[>..];
reusable[] var checked_nominals:Nominal[>..];
reusable[] var checked_contracts:Contract[>..];
reusable[] var checked_contract_predicates:squid_check_types::Obligation[>..];
reusable[] var checked_contract_members:ContractMember[>..];
reusable[] var checked_implementations:Implementation[>..];
reusable[] var checked_implementation_predicates:squid_check_types::Obligation[>..];
reusable[] var checked_implementation_members:ImplementationMember[>..];
reusable[] var checked_member_templates:squid_reuse_principal_interface::MemberTemplate[>..];
reusable[] var checked_constructors:Constructor[>..];
reusable[] var checked_constructor_resolved:u32[>..];
reusable[] var checked_projections:u32[>..];
reusable[] var checked_access_paths:squid_check_types::List[>..];
reusable[] var checked_access_nodes:squid_check_types::List[>..];
reusable[] var checked_access_types:squid_check_types::List[>..];
reusable[] var checked_projection_resolved:u32[>..];
reusable[] var checked_projection_catalog:Projection[>..];
reusable[] var checked_rebindings:Rebinding[>..];
reusable[] var checked_loop_carries:LoopCarry[>..];
reusable[] var checked_loop_ranges:squid_check_types::List[>..];
reusable[] var checked_loop_exits:LoopExit[>..];
reusable[] var checked_statement_arms:StatementArm[>..];
reusable[] var checked_declarations:SourceDeclaration[>..];
reusable[] var checked_editor_names:EditorName[>..];
fn valid(self_:CheckedOwner)->bool {return self_.lease!=0 && self_.lease-1<checked_owners.len && checked_owners[self_.lease-1].live && checked_owners[self_.lease-1].generation==self_.generation;}
fn checkedOwnerState(self_:CheckedOwner)->CheckedOwnerState& {assert(self_.valid());return checked_owners[self_.lease-1];}
fn newCheckedOwner()->CheckedOwner,squid_error::Error {if checked_owners.len>=0xffffffff {return CheckedOwner{..},squid_error::Error.out_of_memory;}let generation=squid_native::fresh_owner_id();let index=checked_owners.alloc_index(CheckedOwnerState{generation:generation,live:true, ..});return CheckedOwner{(index+1) as u32,generation, ..},squid_error::Error.none;}
fn ownChecked_function_exit_lambdas(owner:CheckedOwner,values:const squid_parse_ast::Id[:])->squid_parse_ast::Id[:] {let state .= checkedOwnerState(owner);assert(state.function_exit_lambdas.len==0);let result=checked_function_exit_lambdas.alloc_slice(values.len);for value,index in values {result[index]=value;}state.function_exit_lambdas=result;return result;}
fn ownChecked_iterator_bodies(owner:CheckedOwner,values:const squid_parse_ast::Id[:])->squid_parse_ast::Id[:] {let state .= checkedOwnerState(owner);assert(state.iterator_bodies.len==0);let result=checked_iterator_bodies.alloc_slice(values.len);for value,index in values {result[index]=value;}state.iterator_bodies=result;return result;}
fn ownChecked_computations(owner:CheckedOwner,values:const Computation[:])->Computation[:] {let state .= checkedOwnerState(owner);assert(state.computations.len==0);let result=checked_computations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.computations=result;return result;}
fn ownChecked_reflections(owner:CheckedOwner,values:const Reflection[:])->Reflection[:] {let state .= checkedOwnerState(owner);assert(state.reflections.len==0);let result=checked_reflections.alloc_slice(values.len);for value,index in values {result[index]=value;}state.reflections=result;return result;}
fn ownChecked_tag_origins(owner:CheckedOwner,values:const TagOrigin[:])->TagOrigin[:] {let state .= checkedOwnerState(owner);assert(state.tag_origins.len==0);let result=checked_tag_origins.alloc_slice(values.len);for value,index in values {result[index]=value;}state.tag_origins=result;return result;}
fn ownChecked_effect_runners(owner:CheckedOwner,values:const EffectRunner[:])->EffectRunner[:] {let state .= checkedOwnerState(owner);assert(state.effect_runners.len==0);let result=checked_effect_runners.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_runners=result;return result;}
fn ownChecked_effect_runner_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.effect_runner_ids.len==0);let result=checked_effect_runner_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_runner_ids=result;return result;}
fn ownChecked_provider_blocks(owner:CheckedOwner,values:const ProviderBlock[:])->ProviderBlock[:] {let state .= checkedOwnerState(owner);assert(state.provider_blocks.len==0);let result=checked_provider_blocks.alloc_slice(values.len);for value,index in values {result[index]=value;}state.provider_blocks=result;return result;}
fn ownChecked_provider_block_ids(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.provider_block_ids.len==0);let result=checked_provider_block_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}state.provider_block_ids=result;return result;}
fn ownChecked_body_closed_rows(owner:CheckedOwner,values:const ClosedRow[:])->ClosedRow[:] {let state .= checkedOwnerState(owner);assert(state.body_closed_rows.len==0);let result=checked_body_closed_rows.alloc_slice(values.len);for value,index in values {result[index]=value;}state.body_closed_rows=result;return result;}
fn ownChecked_lambda_closed_rows(owner:CheckedOwner,values:const squid_check_types::List[:])->squid_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.lambda_closed_rows.len==0);let result=checked_lambda_closed_rows.alloc_slice(values.len);for value,index in values {result[index]=value;}state.lambda_closed_rows=result;return result;}
fn ownChecked_dispatch_signatures(owner:CheckedOwner,values:const squid_check_types::Id[:])->squid_check_types::Id[:] {let state .= checkedOwnerState(owner);assert(state.dispatch_signatures.len==0);let result=checked_dispatch_signatures.alloc_slice(values.len);for value,index in values {result[index]=value;}state.dispatch_signatures=result;return result;}
fn ownChecked_covered_requirements(owner:CheckedOwner,values:const CoveredRequirement[:])->CoveredRequirement[:] {let state .= checkedOwnerState(owner);assert(state.covered_requirements.len==0);let result=checked_covered_requirements.alloc_slice(values.len);for value,index in values {result[index]=value;}state.covered_requirements=result;return result;}
fn ownChecked_effect_families(owner:CheckedOwner,values:const EffectFamily[:])->EffectFamily[:] {let state .= checkedOwnerState(owner);assert(state.effect_families.len==0);let result=checked_effect_families.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_families=result;return result;}
fn ownChecked_effect_templates(owner:CheckedOwner,values:const EffectTemplate[:])->EffectTemplate[:] {let state .= checkedOwnerState(owner);assert(state.effect_templates.len==0);let result=checked_effect_templates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.effect_templates=result;return result;}
fn ownChecked_operation_uses(owner:CheckedOwner,values:const OperationUse[:])->OperationUse[:] {let state .= checkedOwnerState(owner);assert(state.operation_uses.len==0);let result=checked_operation_uses.alloc_slice(values.len);for value,index in values {result[index]=value;}state.operation_uses=result;return result;}
fn ownChecked_operation_refs(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.operation_refs.len==0);let result=checked_operation_refs.alloc_slice(values.len);for value,index in values {result[index]=value;}state.operation_refs=result;return result;}
fn ownChecked_expr_types(owner:CheckedOwner,values:const squid_check_types::Id[:])->squid_check_types::Id[:] {let state .= checkedOwnerState(owner);assert(state.expr_types.len==0);let result=checked_expr_types.alloc_slice(values.len);for value,index in values {result[index]=value;}state.expr_types=result;return result;}
fn ownChecked_resolved(owner:CheckedOwner,values:const BindingId[:])->BindingId[:] {let state .= checkedOwnerState(owner);assert(state.resolved.len==0);let result=checked_resolved.alloc_slice(values.len);for value,index in values {result[index]=value;}state.resolved=result;return result;}
fn ownChecked_bindings(owner:CheckedOwner,values:const Binding[:])->Binding[:] {let state .= checkedOwnerState(owner);assert(state.bindings.len==0);let result=checked_bindings.alloc_slice(values.len);for value,index in values {result[index]=value;}state.bindings=result;return result;}
fn ownChecked_merges(owner:CheckedOwner,values:const Merge[:])->Merge[:] {let state .= checkedOwnerState(owner);assert(state.merges.len==0);let result=checked_merges.alloc_slice(values.len);for value,index in values {result[index]=value;}state.merges=result;return result;}
fn ownChecked_obligations(owner:CheckedOwner,values:const squid_check_types::Obligation[:])->squid_check_types::Obligation[:] {let state .= checkedOwnerState(owner);assert(state.obligations.len==0);let result=checked_obligations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.obligations=result;return result;}
fn cloneDiagnosticPurity(value:PurityWitness)->PurityWitness {
 var name=squid_support::none<const u8[:]>();if value.operation_name.present {name=squid_support::some<const u8[:]>(ownDiagnosticText(value.operation_name.value));}
 return PurityWitness{identity:value.identity,family:value.family,member:value.member,compound:value.compound,foreign:value.foreign,
  specialized:value.specialized,origin_unavailable:value.origin_unavailable,operation_name:name};
}
// Publish scalar metadata first. cloneDiagnostics installs independently owned
// text, hole and explanation payloads after this run has a cleanup owner.
fn ownChecked_diagnostics(owner:CheckedOwner,values:const Diagnostic[:])->Diagnostic[:] {
 let state .= checkedOwnerState(owner);assert(state.diagnostics.len==0);let result=checked_diagnostics.alloc_slice(values.len);
 for value,index in values {result[index]=Diagnostic{origin_unit:value.origin_unit,code:value.code,span:value.span,node:value.node,
  type_application:value.type_application,symbol:value.symbol,implicit_type_witness:value.implicit_type_witness,source_terminator:value.source_terminator,
  numeric_literal:value.numeric_literal,contexts:value.contexts,context_len:value.context_len,..};}
 state.diagnostics=result;return result;
}
fn ownChecked_associated(owner:CheckedOwner,values:const Associated[:])->Associated[:] {let state .= checkedOwnerState(owner);assert(state.associated.len==0);let result=checked_associated.alloc_slice(values.len);for value,index in values {result[index]=value;}state.associated=result;return result;}
fn ownChecked_nominals(owner:CheckedOwner,values:const Nominal[:])->Nominal[:] {let state .= checkedOwnerState(owner);assert(state.nominals.len==0);let result=checked_nominals.alloc_slice(values.len);for value,index in values {result[index]=value;}state.nominals=result;return result;}
fn ownChecked_contracts(owner:CheckedOwner,values:const Contract[:])->Contract[:] {let state .= checkedOwnerState(owner);assert(state.contracts.len==0);let result=checked_contracts.alloc_slice(values.len);for value,index in values {result[index]=value;}state.contracts=result;return result;}
fn ownChecked_contract_predicates(owner:CheckedOwner,values:const squid_check_types::Obligation[:])->squid_check_types::Obligation[:] {let state .= checkedOwnerState(owner);assert(state.contract_predicates.len==0);let result=checked_contract_predicates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.contract_predicates=result;return result;}
fn ownChecked_contract_members(owner:CheckedOwner,values:const ContractMember[:])->ContractMember[:] {let state .= checkedOwnerState(owner);assert(state.contract_members.len==0);let result=checked_contract_members.alloc_slice(values.len);for value,index in values {result[index]=value;}state.contract_members=result;return result;}
fn ownChecked_implementations(owner:CheckedOwner,values:const Implementation[:])->Implementation[:] {let state .= checkedOwnerState(owner);assert(state.implementations.len==0);let result=checked_implementations.alloc_slice(values.len);for value,index in values {result[index]=value;}state.implementations=result;return result;}
fn ownChecked_implementation_predicates(owner:CheckedOwner,values:const squid_check_types::Obligation[:])->squid_check_types::Obligation[:] {let state .= checkedOwnerState(owner);assert(state.implementation_predicates.len==0);let result=checked_implementation_predicates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.implementation_predicates=result;return result;}
fn ownChecked_implementation_members(owner:CheckedOwner,values:const ImplementationMember[:])->ImplementationMember[:] {let state .= checkedOwnerState(owner);assert(state.implementation_members.len==0);let result=checked_implementation_members.alloc_slice(values.len);for value,index in values {result[index]=value;}state.implementation_members=result;return result;}
fn ownChecked_member_templates(owner:CheckedOwner,values:const squid_reuse_principal_interface::MemberTemplate[:])->squid_reuse_principal_interface::MemberTemplate[:] {let state .= checkedOwnerState(owner);assert(state.member_templates.len==0);let result=checked_member_templates.alloc_slice(values.len);for value,index in values {result[index]=value;}state.member_templates=result;return result;}
fn ownChecked_constructors(owner:CheckedOwner,values:const Constructor[:])->Constructor[:] {let state .= checkedOwnerState(owner);assert(state.constructors.len==0);let result=checked_constructors.alloc_slice(values.len);for value,index in values {result[index]=value;}state.constructors=result;return result;}
fn ownChecked_constructor_resolved(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.constructor_resolved.len==0);let result=checked_constructor_resolved.alloc_slice(values.len);for value,index in values {result[index]=value;}state.constructor_resolved=result;return result;}
fn ownChecked_projections(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.projections.len==0);let result=checked_projections.alloc_slice(values.len);for value,index in values {result[index]=value;}state.projections=result;return result;}
fn ownChecked_access_paths(owner:CheckedOwner,values:const squid_check_types::List[:])->squid_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.access_paths.len==0);let result=checked_access_paths.alloc_slice(values.len);for value,index in values {result[index]=value;}state.access_paths=result;return result;}
fn ownChecked_access_nodes(owner:CheckedOwner,values:const squid_check_types::List[:])->squid_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.access_nodes.len==0);let result=checked_access_nodes.alloc_slice(values.len);for value,index in values {result[index]=value;}state.access_nodes=result;return result;}
fn ownChecked_access_types(owner:CheckedOwner,values:const squid_check_types::List[:])->squid_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.access_types.len==0);let result=checked_access_types.alloc_slice(values.len);for value,index in values {result[index]=value;}state.access_types=result;return result;}
fn ownChecked_projection_resolved(owner:CheckedOwner,values:const u32[:])->u32[:] {let state .= checkedOwnerState(owner);assert(state.projection_resolved.len==0);let result=checked_projection_resolved.alloc_slice(values.len);for value,index in values {result[index]=value;}state.projection_resolved=result;return result;}
fn ownChecked_projection_catalog(owner:CheckedOwner,values:const Projection[:])->Projection[:] {let state .= checkedOwnerState(owner);assert(state.projection_catalog.len==0);let result=checked_projection_catalog.alloc_slice(values.len);for value,index in values {result[index]=value;}state.projection_catalog=result;return result;}
fn ownChecked_rebindings(owner:CheckedOwner,values:const Rebinding[:])->Rebinding[:] {let state .= checkedOwnerState(owner);assert(state.rebindings.len==0);let result=checked_rebindings.alloc_slice(values.len);for value,index in values {result[index]=value;}state.rebindings=result;return result;}
fn ownChecked_loop_carries(owner:CheckedOwner,values:const LoopCarry[:])->LoopCarry[:] {let state .= checkedOwnerState(owner);assert(state.loop_carries.len==0);let result=checked_loop_carries.alloc_slice(values.len);for value,index in values {result[index]=value;}state.loop_carries=result;return result;}
fn ownChecked_loop_ranges(owner:CheckedOwner,values:const squid_check_types::List[:])->squid_check_types::List[:] {let state .= checkedOwnerState(owner);assert(state.loop_ranges.len==0);let result=checked_loop_ranges.alloc_slice(values.len);for value,index in values {result[index]=value;}state.loop_ranges=result;return result;}
fn ownChecked_loop_exits(owner:CheckedOwner,values:const LoopExit[:])->LoopExit[:] {let state .= checkedOwnerState(owner);assert(state.loop_exits.len==0);let result=checked_loop_exits.alloc_slice(values.len);for value,index in values {result[index]=value;}state.loop_exits=result;return result;}
fn ownChecked_statement_arms(owner:CheckedOwner,values:const StatementArm[:])->StatementArm[:] {let state .= checkedOwnerState(owner);assert(state.statement_arms.len==0);let result=checked_statement_arms.alloc_slice(values.len);for value,index in values {result[index]=value;}state.statement_arms=result;return result;}
fn ownChecked_declarations(owner:CheckedOwner,values:const SourceDeclaration[:])->SourceDeclaration[:] {let state .= checkedOwnerState(owner);assert(state.declarations.len==0);let result=checked_declarations.alloc_slice(values.len);for value,index in values {result[index]=SourceDeclaration{capability_parameters:value.capability_parameters,private:value.private,name:value.name,declaration:value.declaration,kind:value.kind,named_function:value.named_function,external:value.external};}state.declarations=result;return ownedSourceDeclarations(owner);}
fn ownChecked_editor_names(owner:CheckedOwner,values:const EditorName[:])->EditorName[:] {let state .= checkedOwnerState(owner);assert(state.editor_names.len==0);let result=checked_editor_names.alloc_slice(values.len);for value,index in values {result[index]=value;}state.editor_names=result;return result;}
// Publication recovers only the exact arrays registered by this Checked owner.
fn ownedSourceDeclarations(owner:CheckedOwner)->SourceDeclaration[:] {let state .= checkedOwnerState(owner);let values=checked_declarations.realloc_slice(state.declarations,state.declarations.len);assert(squid_support::same_slice_identity(values,state.declarations));return values;}
fn sourceValidationPatterns(store:squid_check_parameter_patterns::Store)->squid_check_parameter_patterns::Store {if store.lease==0 {assert(store.generation==0);return squid_check_parameter_patterns::Store{..};}return squid_check_parameter_patterns::checkedView(store);}
fn ownedSourceValidation(checked:const Checked&,declarations:const SourceDeclaration[:])->SourceValidation {
 let owner=checked.owner;let state .= checkedOwnerState(owner);
 assert(squid_support::same_slice_identity(state.declarations,declarations));
 assert(squid_support::same_slice_identity(state.resolved,checked.resolved));
 assert(squid_support::same_slice_identity(state.nominals,checked.nominals));
 assert(squid_support::same_slice_identity(state.contracts,checked.contracts));
 assert(squid_support::same_slice_identity(state.contract_predicates,checked.contract_predicates));
 assert(squid_support::same_slice_identity(state.contract_members,checked.contract_members));
 assert(squid_support::same_slice_identity(state.implementations,checked.implementations));
 assert(squid_support::same_slice_identity(state.implementation_predicates,checked.implementation_predicates));
 assert(squid_support::same_slice_identity(state.implementation_members,checked.implementation_members));
 assert(squid_support::same_slice_identity(state.member_templates,checked.member_templates));
 assert(squid_support::same_slice_identity(state.constructors,checked.constructors));
 assert(squid_support::same_slice_identity(state.effect_families,checked.effect_families));
 assert(squid_support::same_slice_identity(state.effect_templates,checked.effect_templates));
 assert(squid_support::same_slice_identity(state.associated,checked.associated));
 assert(squid_support::same_slice_identity(state.diagnostics,checked.diagnostics));
 return SourceValidation{owner:CheckedOwner{lease:owner.lease,generation:owner.generation},types:squid_check_types::checkedView(checked.types),parameter_patterns:sourceValidationPatterns(checked.parameter_patterns),
 declarations:checked_declarations.realloc_slice(state.declarations,state.declarations.len),
 resolved:checked_resolved.realloc_slice(state.resolved,state.resolved.len),
 nominals:checked_nominals.realloc_slice(state.nominals,state.nominals.len),
 contracts:checked_contracts.realloc_slice(state.contracts,state.contracts.len),
 contract_predicates:checked_contract_predicates.realloc_slice(state.contract_predicates,state.contract_predicates.len),
 contract_members:checked_contract_members.realloc_slice(state.contract_members,state.contract_members.len),
 implementations:checked_implementations.realloc_slice(state.implementations,state.implementations.len),
 implementation_predicates:checked_implementation_predicates.realloc_slice(state.implementation_predicates,state.implementation_predicates.len),
 implementation_members:checked_implementation_members.realloc_slice(state.implementation_members,state.implementation_members.len),
 member_templates:checked_member_templates.realloc_slice(state.member_templates,state.member_templates.len),
 constructors:checked_constructors.realloc_slice(state.constructors,state.constructors.len),
 effect_families:checked_effect_families.realloc_slice(state.effect_families,state.effect_families.len),
 effect_templates:checked_effect_templates.realloc_slice(state.effect_templates,state.effect_templates.len),
 associated:checked_associated.realloc_slice(state.associated,state.associated.len),
 diagnostics:checked_diagnostics.realloc_slice(state.diagnostics,state.diagnostics.len),
 unit:checked.unit};
}
fn releaseCheckedBodies(owner:CheckedOwner) {let state .= checkedOwnerState(owner);
if state.function_exit_lambdas.len!=0 {checked_function_exit_lambdas.free_slice(state.function_exit_lambdas);state.function_exit_lambdas=default<squid_parse_ast::Id[:]>();}
if state.iterator_bodies.len!=0 {checked_iterator_bodies.free_slice(state.iterator_bodies);state.iterator_bodies=default<squid_parse_ast::Id[:]>();}
if state.computations.len!=0 {checked_computations.free_slice(state.computations);state.computations=default<Computation[:]>();}
if state.reflections.len!=0 {checked_reflections.free_slice(state.reflections);state.reflections=default<Reflection[:]>();}
if state.tag_origins.len!=0 {checked_tag_origins.free_slice(state.tag_origins);state.tag_origins=default<TagOrigin[:]>();}
if state.effect_runners.len!=0 {checked_effect_runners.free_slice(state.effect_runners);state.effect_runners=default<EffectRunner[:]>();}
if state.effect_runner_ids.len!=0 {checked_effect_runner_ids.free_slice(state.effect_runner_ids);state.effect_runner_ids=default<u32[:]>();}
if state.provider_blocks.len!=0 {checked_provider_blocks.free_slice(state.provider_blocks);state.provider_blocks=default<ProviderBlock[:]>();}
if state.provider_block_ids.len!=0 {checked_provider_block_ids.free_slice(state.provider_block_ids);state.provider_block_ids=default<u32[:]>();}
if state.body_closed_rows.len!=0 {checked_body_closed_rows.free_slice(state.body_closed_rows);state.body_closed_rows=default<ClosedRow[:]>();}
if state.lambda_closed_rows.len!=0 {checked_lambda_closed_rows.free_slice(state.lambda_closed_rows);state.lambda_closed_rows=default<squid_check_types::List[:]>();}
if state.dispatch_signatures.len!=0 {checked_dispatch_signatures.free_slice(state.dispatch_signatures);state.dispatch_signatures=default<squid_check_types::Id[:]>();}
if state.covered_requirements.len!=0 {checked_covered_requirements.free_slice(state.covered_requirements);state.covered_requirements=default<CoveredRequirement[:]>();}
if state.operation_uses.len!=0 {checked_operation_uses.free_slice(state.operation_uses);state.operation_uses=default<OperationUse[:]>();}
if state.operation_refs.len!=0 {checked_operation_refs.free_slice(state.operation_refs);state.operation_refs=default<u32[:]>();}
if state.expr_types.len!=0 {checked_expr_types.free_slice(state.expr_types);state.expr_types=default<squid_check_types::Id[:]>();}
if state.bindings.len!=0 {checked_bindings.free_slice(state.bindings);state.bindings=default<Binding[:]>();}
if state.merges.len!=0 {checked_merges.free_slice(state.merges);state.merges=default<Merge[:]>();}
if state.obligations.len!=0 {checked_obligations.free_slice(state.obligations);state.obligations=default<squid_check_types::Obligation[:]>();}
if state.constructor_resolved.len!=0 {checked_constructor_resolved.free_slice(state.constructor_resolved);state.constructor_resolved=default<u32[:]>();}
if state.projections.len!=0 {checked_projections.free_slice(state.projections);state.projections=default<u32[:]>();}
if state.access_paths.len!=0 {checked_access_paths.free_slice(state.access_paths);state.access_paths=default<squid_check_types::List[:]>();}
if state.access_nodes.len!=0 {checked_access_nodes.free_slice(state.access_nodes);state.access_nodes=default<squid_check_types::List[:]>();}
if state.access_types.len!=0 {checked_access_types.free_slice(state.access_types);state.access_types=default<squid_check_types::List[:]>();}
if state.projection_resolved.len!=0 {checked_projection_resolved.free_slice(state.projection_resolved);state.projection_resolved=default<u32[:]>();}
if state.projection_catalog.len!=0 {checked_projection_catalog.free_slice(state.projection_catalog);state.projection_catalog=default<Projection[:]>();}
if state.rebindings.len!=0 {checked_rebindings.free_slice(state.rebindings);state.rebindings=default<Rebinding[:]>();}
if state.loop_carries.len!=0 {checked_loop_carries.free_slice(state.loop_carries);state.loop_carries=default<LoopCarry[:]>();}
if state.loop_ranges.len!=0 {checked_loop_ranges.free_slice(state.loop_ranges);state.loop_ranges=default<squid_check_types::List[:]>();}
if state.loop_exits.len!=0 {checked_loop_exits.free_slice(state.loop_exits);state.loop_exits=default<LoopExit[:]>();}
if state.statement_arms.len!=0 {checked_statement_arms.free_slice(state.statement_arms);state.statement_arms=default<StatementArm[:]>();}
if state.editor_names.len!=0 {checked_editor_names.free_slice(state.editor_names);state.editor_names=default<EditorName[:]>();}
}
fn deinit(self_:CheckedOwner&) {if self_.lease==0 {return;}assert(self_.valid());let state .= checkedOwnerState(self_);
if state.function_exit_lambdas.len!=0 {checked_function_exit_lambdas.free_slice(state.function_exit_lambdas);state.function_exit_lambdas=default<squid_parse_ast::Id[:]>();}
if state.iterator_bodies.len!=0 {checked_iterator_bodies.free_slice(state.iterator_bodies);state.iterator_bodies=default<squid_parse_ast::Id[:]>();}
if state.computations.len!=0 {checked_computations.free_slice(state.computations);state.computations=default<Computation[:]>();}
if state.reflections.len!=0 {checked_reflections.free_slice(state.reflections);state.reflections=default<Reflection[:]>();}
if state.tag_origins.len!=0 {checked_tag_origins.free_slice(state.tag_origins);state.tag_origins=default<TagOrigin[:]>();}
if state.effect_runners.len!=0 {checked_effect_runners.free_slice(state.effect_runners);state.effect_runners=default<EffectRunner[:]>();}
if state.effect_runner_ids.len!=0 {checked_effect_runner_ids.free_slice(state.effect_runner_ids);state.effect_runner_ids=default<u32[:]>();}
if state.provider_blocks.len!=0 {checked_provider_blocks.free_slice(state.provider_blocks);state.provider_blocks=default<ProviderBlock[:]>();}
if state.provider_block_ids.len!=0 {checked_provider_block_ids.free_slice(state.provider_block_ids);state.provider_block_ids=default<u32[:]>();}
if state.body_closed_rows.len!=0 {checked_body_closed_rows.free_slice(state.body_closed_rows);state.body_closed_rows=default<ClosedRow[:]>();}
if state.lambda_closed_rows.len!=0 {checked_lambda_closed_rows.free_slice(state.lambda_closed_rows);state.lambda_closed_rows=default<squid_check_types::List[:]>();}
if state.dispatch_signatures.len!=0 {checked_dispatch_signatures.free_slice(state.dispatch_signatures);state.dispatch_signatures=default<squid_check_types::Id[:]>();}
if state.covered_requirements.len!=0 {checked_covered_requirements.free_slice(state.covered_requirements);state.covered_requirements=default<CoveredRequirement[:]>();}
if state.effect_families.len!=0 {checked_effect_families.free_slice(state.effect_families);state.effect_families=default<EffectFamily[:]>();}
if state.effect_templates.len!=0 {checked_effect_templates.free_slice(state.effect_templates);state.effect_templates=default<EffectTemplate[:]>();}
if state.operation_uses.len!=0 {checked_operation_uses.free_slice(state.operation_uses);state.operation_uses=default<OperationUse[:]>();}
if state.operation_refs.len!=0 {checked_operation_refs.free_slice(state.operation_refs);state.operation_refs=default<u32[:]>();}
if state.expr_types.len!=0 {checked_expr_types.free_slice(state.expr_types);state.expr_types=default<squid_check_types::Id[:]>();}
if state.resolved.len!=0 {checked_resolved.free_slice(state.resolved);state.resolved=default<BindingId[:]>();}
if state.bindings.len!=0 {checked_bindings.free_slice(state.bindings);state.bindings=default<Binding[:]>();}
if state.merges.len!=0 {checked_merges.free_slice(state.merges);state.merges=default<Merge[:]>();}
if state.obligations.len!=0 {checked_obligations.free_slice(state.obligations);state.obligations=default<squid_check_types::Obligation[:]>();}
if state.diagnostics.len!=0 {checked_diagnostics.free_slice(state.diagnostics);state.diagnostics=default<Diagnostic[:]>();}
if state.associated.len!=0 {checked_associated.free_slice(state.associated);state.associated=default<Associated[:]>();}
if state.nominals.len!=0 {checked_nominals.free_slice(state.nominals);state.nominals=default<Nominal[:]>();}
if state.contracts.len!=0 {checked_contracts.free_slice(state.contracts);state.contracts=default<Contract[:]>();}
if state.contract_predicates.len!=0 {checked_contract_predicates.free_slice(state.contract_predicates);state.contract_predicates=default<squid_check_types::Obligation[:]>();}
if state.contract_members.len!=0 {checked_contract_members.free_slice(state.contract_members);state.contract_members=default<ContractMember[:]>();}
if state.implementations.len!=0 {checked_implementations.free_slice(state.implementations);state.implementations=default<Implementation[:]>();}
if state.implementation_predicates.len!=0 {checked_implementation_predicates.free_slice(state.implementation_predicates);state.implementation_predicates=default<squid_check_types::Obligation[:]>();}
if state.implementation_members.len!=0 {checked_implementation_members.free_slice(state.implementation_members);state.implementation_members=default<ImplementationMember[:]>();}
if state.member_templates.len!=0 {checked_member_templates.free_slice(state.member_templates);state.member_templates=default<squid_reuse_principal_interface::MemberTemplate[:]>();}
if state.constructors.len!=0 {checked_constructors.free_slice(state.constructors);state.constructors=default<Constructor[:]>();}
if state.constructor_resolved.len!=0 {checked_constructor_resolved.free_slice(state.constructor_resolved);state.constructor_resolved=default<u32[:]>();}
if state.projections.len!=0 {checked_projections.free_slice(state.projections);state.projections=default<u32[:]>();}
if state.access_paths.len!=0 {checked_access_paths.free_slice(state.access_paths);state.access_paths=default<squid_check_types::List[:]>();}
if state.access_nodes.len!=0 {checked_access_nodes.free_slice(state.access_nodes);state.access_nodes=default<squid_check_types::List[:]>();}
if state.access_types.len!=0 {checked_access_types.free_slice(state.access_types);state.access_types=default<squid_check_types::List[:]>();}
if state.projection_resolved.len!=0 {checked_projection_resolved.free_slice(state.projection_resolved);state.projection_resolved=default<u32[:]>();}
if state.projection_catalog.len!=0 {checked_projection_catalog.free_slice(state.projection_catalog);state.projection_catalog=default<Projection[:]>();}
if state.rebindings.len!=0 {checked_rebindings.free_slice(state.rebindings);state.rebindings=default<Rebinding[:]>();}
if state.loop_carries.len!=0 {checked_loop_carries.free_slice(state.loop_carries);state.loop_carries=default<LoopCarry[:]>();}
if state.loop_ranges.len!=0 {checked_loop_ranges.free_slice(state.loop_ranges);state.loop_ranges=default<squid_check_types::List[:]>();}
if state.loop_exits.len!=0 {checked_loop_exits.free_slice(state.loop_exits);state.loop_exits=default<LoopExit[:]>();}
if state.statement_arms.len!=0 {checked_statement_arms.free_slice(state.statement_arms);state.statement_arms=default<StatementArm[:]>();}
if state.declarations.len!=0 {checked_declarations.free_slice(state.declarations);state.declarations=default<SourceDeclaration[:]>();}
if state.editor_names.len!=0 {checked_editor_names.free_slice(state.editor_names);state.editor_names=default<EditorName[:]>();}
let index=self_.lease-1;state.live=false;checked_owners.free(index);self_=CheckedOwner{..};}
fn deinit(self_:Checked&) {if !self_.owner.valid() {return;}deinitDiagnosticPayloads(self_.diagnostics);if self_.editor.present && self_.editor.value.context.present {self_.editor.value.context.value.deinit();}self_.types.deinit();self_.parameter_patterns.deinit();releaseCheckedPacket(self_.owner);self_.owner.deinit();self_=default<Checked>();}
fn deinit(self_:SourceValidation&) {if !self_.owner.valid() {return;}deinitDiagnosticPayloads(self_.diagnostics);self_.types.deinit();self_.parameter_patterns.deinit();self_.owner.deinit();self_=default<SourceValidation>();}
