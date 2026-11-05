// Exact typed ownership for unpublished dependency/Core/principal payloads.
// All immutable views name registered runs; no const cast or host pointer image.
namespace blot_reuse_dependency_payload;
import backend.collection_ops;
import backend.opaque_storage;
import check.capability_contracts;
import check.capability_flow;
import check.core;
import check.effects;
import check.frozen_types;
import check.numeric_proof_contracts;
import check.numeric_proof_headers;
import check.numeric_proof_terms;
import check.parameter_patterns;
import check.types;
import parse.ast;
import reuse.frozen_dependency;
import reuse.principal_interface;
import support.error;
import support.native;
import support.option;

type Error=blot_error::Error;
struct Owner {lease:u32=0,generation:u64=0}
struct Owned<T> {value:T,owner:Owner=Owner {}}

enum Run {
run_u32 {values:u32[:]},
run_blot_check_numeric_proof_terms__Kind {values:blot_check_numeric_proof_terms::Kind[:]},
run_blot_check_numeric_proof_terms__Term {values:blot_check_numeric_proof_terms::Term[:]},
run_blot_check_numeric_proof_contracts__Requirement {values:blot_check_numeric_proof_contracts::Requirement[:]},
run_blot_check_numeric_proof_headers__Named {values:blot_check_numeric_proof_headers::Named[:]},
run_blot_check_capability_contracts__Term {values:blot_check_capability_contracts::Term[:]},
run_blot_check_capability_contracts__Binding {values:blot_check_capability_contracts::Binding[:]},
run_blot_check_core__FieldName {values:blot_check_core::FieldName[:]},
run_blot_check_core__RuntimeName {values:blot_check_core::RuntimeName[:]},
run_blot_check_core__DeclarationDependencies {values:blot_check_core::DeclarationDependencies[:]},
run_blot_check_core__BindingRef {values:blot_check_core::BindingRef[:]},
run_blot_check_core__DependencyMember {values:blot_check_core::DependencyMember[:]},
run_blot_check_core__ErasedDeclarationReference {values:blot_check_core::ErasedDeclarationReference[:]},
run_blot_check_core__RequestLoopInfo {values:blot_check_core::RequestLoopInfo[:]},
run_blot_check_core__RequestArm {values:blot_check_core::RequestArm[:]},
run_blot_check_types__Node {values:blot_check_types::Node[:]},
run_blot_check_effects__Row {values:blot_check_effects::Row[:]},
run_blot_check_types__Operation {values:blot_check_types::Operation[:]},
run_blot_check_types__QuantifierGoals {values:blot_check_types::QuantifierGoals[:]},
run_blot_check_types__Obligation {values:blot_check_types::Obligation[:]},
run_blot_check_core__Node {values:blot_check_core::Node[:]},
run_blot_parse_ast__Span {values:blot_parse_ast::Span[:]},
run_blot_check_core__Binding {values:blot_check_core::Binding[:]},
run_blot_check_core__Body {values:blot_check_core::Body[:]},
run_blot_check_core__Parameter {values:blot_check_core::Parameter[:]},
run_blot_check_core__CallInfo {values:blot_check_core::CallInfo[:]},
run_blot_check_core__Merge {values:blot_check_core::Merge[:]},
run_blot_check_core__List {values:blot_check_core::List[:]},
run_u8 {values:u8[:]},
run_blot_check_core__Obligation {values:blot_check_core::Obligation[:]},
run_blot_check_core__Nominal {values:blot_check_core::Nominal[:]},
run_blot_check_core__OperationName {values:blot_check_core::OperationName[:]},
run_blot_check_core__Constructor {values:blot_check_core::Constructor[:]},
run_blot_check_core__Projection {values:blot_check_core::Projection[:]},
run_blot_check_core__ProjectionVariant {values:blot_check_core::ProjectionVariant[:]},
run_blot_check_core__Pattern {values:blot_check_core::Pattern[:]},
run_blot_check_core__PatternRow {values:blot_check_core::PatternRow[:]},
run_blot_check_core__MatchArm {values:blot_check_core::MatchArm[:]},
run_blot_check_core__MatchInfo {values:blot_check_core::MatchInfo[:]},
run_blot_check_core__UpdateInfo {values:blot_check_core::UpdateInfo[:]},
run_blot_check_core__UpdateStep {values:blot_check_core::UpdateStep[:]},
run_blot_check_core__ClosureInfo {values:blot_check_core::ClosureInfo[:]},
run_blot_check_core__Associated {values:blot_check_core::Associated[:]},
run_blot_check_core__Contract {values:blot_check_core::Contract[:]},
run_blot_reuse_principal_interface__ContractMember {values:blot_reuse_principal_interface::ContractMember[:]},
run_blot_reuse_principal_interface__Implementation {values:blot_reuse_principal_interface::Implementation[:]},
run_blot_reuse_principal_interface__ImplementationMember {values:blot_reuse_principal_interface::ImplementationMember[:]},
run_blot_reuse_principal_interface__MemberTemplate {values:blot_reuse_principal_interface::MemberTemplate[:]},
run_blot_reuse_principal_interface__SelectedProof {values:blot_reuse_principal_interface::SelectedProof[:]},
run_blot_check_core__SelectedUse {values:blot_check_core::SelectedUse[:]},
run_blot_check_core__DictionarySelection {values:blot_check_core::DictionarySelection[:]},
run_blot_check_core__DictionaryUse {values:blot_check_core::DictionaryUse[:]},
run_blot_check_core__Primitive {values:blot_check_core::Primitive[:]},
run_blot_check_core__LoopInfo {values:blot_check_core::LoopInfo[:]},
run_blot_check_core__LoopCarry {values:blot_check_core::LoopCarry[:]},
run_blot_check_core__ResolverInfo {values:blot_check_core::ResolverInfo[:]},
run_blot_check_core__OperationValue {values:blot_check_core::OperationValue[:]},
run_blot_check_core__HandleEffects {values:blot_check_core::HandleEffects[:]},
run_blot_check_core__Diagnostic {values:blot_check_core::Diagnostic[:]},
run_blot_check_parameter_patterns__Node {values:blot_check_parameter_patterns::Node[:]},
run_blot_reuse_principal_interface__Binding {values:blot_reuse_principal_interface::Binding[:]},
run_blot_reuse_principal_interface__Nominal {values:blot_reuse_principal_interface::Nominal[:]},
run_blot_reuse_principal_interface__Constructor {values:blot_reuse_principal_interface::Constructor[:]},
run_blot_reuse_principal_interface__EffectFamily {values:blot_reuse_principal_interface::EffectFamily[:]},
run_blot_reuse_principal_interface__EffectTemplate {values:blot_reuse_principal_interface::EffectTemplate[:]},
run_blot_reuse_principal_interface__Associated {values:blot_reuse_principal_interface::Associated[:]},
run_blot_reuse_principal_interface__Contract {values:blot_reuse_principal_interface::Contract[:]},
run_blot_reuse_frozen_dependency__ImportResolution {values:blot_reuse_frozen_dependency::ImportResolution[:]},
run_blot_reuse_frozen_dependency__Export {values:blot_reuse_frozen_dependency::Export[:]},
run_blot_reuse_frozen_dependency__Fixity {values:blot_reuse_frozen_dependency::Fixity[:]},
run_blot_reuse_frozen_dependency__Symbol {values:blot_reuse_frozen_dependency::Symbol[:]},
run_blot_reuse_frozen_dependency__Module {values:blot_reuse_frozen_dependency::Module[:]}
}

struct Link {value:Run,next:u32=0}

struct Lease {head:u32=0,generation:u64=0,live:bool=false}

reusable var links:Link[>..]=[];

reusable var leases:Lease[>..]=[];

reusable[] var pool_u32:u32[>..]=[];

reusable[] var pool_blot_check_numeric_proof_terms__Kind:blot_check_numeric_proof_terms::Kind[>..]=[];

reusable[] var pool_blot_check_numeric_proof_terms__Term:blot_check_numeric_proof_terms::Term[>..]=[];

reusable[] var pool_blot_check_numeric_proof_contracts__Requirement:blot_check_numeric_proof_contracts::Requirement[>..]=[];

reusable[] var pool_blot_check_numeric_proof_headers__Named:blot_check_numeric_proof_headers::Named[>..]=[];

reusable[] var pool_blot_check_capability_contracts__Term:blot_check_capability_contracts::Term[>..]=[];

reusable[] var pool_blot_check_capability_contracts__Binding:blot_check_capability_contracts::Binding[>..]=[];

reusable[] var pool_blot_check_core__FieldName:blot_check_core::FieldName[>..]=[];

reusable[] var pool_blot_check_core__RuntimeName:blot_check_core::RuntimeName[>..]=[];

reusable[] var pool_blot_check_core__DeclarationDependencies:blot_check_core::DeclarationDependencies[>..]=[];

reusable[] var pool_blot_check_core__BindingRef:blot_check_core::BindingRef[>..]=[];

reusable[] var pool_blot_check_core__DependencyMember:blot_check_core::DependencyMember[>..]=[];

reusable[] var pool_blot_check_core__ErasedDeclarationReference:blot_check_core::ErasedDeclarationReference[>..]=[];

reusable[] var pool_blot_check_core__RequestLoopInfo:blot_check_core::RequestLoopInfo[>..]=[];

reusable[] var pool_blot_check_core__RequestArm:blot_check_core::RequestArm[>..]=[];

reusable[] var pool_blot_check_types__Node:blot_check_types::Node[>..]=[];

reusable[] var pool_blot_check_effects__Row:blot_check_effects::Row[>..]=[];

reusable[] var pool_blot_check_types__Operation:blot_check_types::Operation[>..]=[];

reusable[] var pool_blot_check_types__QuantifierGoals:blot_check_types::QuantifierGoals[>..]=[];

reusable[] var pool_blot_check_types__Obligation:blot_check_types::Obligation[>..]=[];

reusable[] var pool_blot_check_core__Node:blot_check_core::Node[>..]=[];

reusable[] var pool_blot_parse_ast__Span:blot_parse_ast::Span[>..]=[];

reusable[] var pool_blot_check_core__Binding:blot_check_core::Binding[>..]=[];

reusable[] var pool_blot_check_core__Body:blot_check_core::Body[>..]=[];

reusable[] var pool_blot_check_core__Parameter:blot_check_core::Parameter[>..]=[];

reusable[] var pool_blot_check_core__CallInfo:blot_check_core::CallInfo[>..]=[];

reusable[] var pool_blot_check_core__Merge:blot_check_core::Merge[>..]=[];

reusable[] var pool_blot_check_core__List:blot_check_core::List[>..]=[];

reusable[] var pool_u8:u8[>..]=[];

reusable[] var pool_blot_check_core__Obligation:blot_check_core::Obligation[>..]=[];

reusable[] var pool_blot_check_core__Nominal:blot_check_core::Nominal[>..]=[];

reusable[] var pool_blot_check_core__OperationName:blot_check_core::OperationName[>..]=[];

reusable[] var pool_blot_check_core__Constructor:blot_check_core::Constructor[>..]=[];

reusable[] var pool_blot_check_core__Projection:blot_check_core::Projection[>..]=[];

reusable[] var pool_blot_check_core__ProjectionVariant:blot_check_core::ProjectionVariant[>..]=[];

reusable[] var pool_blot_check_core__Pattern:blot_check_core::Pattern[>..]=[];

reusable[] var pool_blot_check_core__PatternRow:blot_check_core::PatternRow[>..]=[];

reusable[] var pool_blot_check_core__MatchArm:blot_check_core::MatchArm[>..]=[];

reusable[] var pool_blot_check_core__MatchInfo:blot_check_core::MatchInfo[>..]=[];

reusable[] var pool_blot_check_core__UpdateInfo:blot_check_core::UpdateInfo[>..]=[];

reusable[] var pool_blot_check_core__UpdateStep:blot_check_core::UpdateStep[>..]=[];

reusable[] var pool_blot_check_core__ClosureInfo:blot_check_core::ClosureInfo[>..]=[];

reusable[] var pool_blot_check_core__Associated:blot_check_core::Associated[>..]=[];

reusable[] var pool_blot_check_core__Contract:blot_check_core::Contract[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__ContractMember:blot_reuse_principal_interface::ContractMember[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__Implementation:blot_reuse_principal_interface::Implementation[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__ImplementationMember:blot_reuse_principal_interface::ImplementationMember[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__MemberTemplate:blot_reuse_principal_interface::MemberTemplate[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__SelectedProof:blot_reuse_principal_interface::SelectedProof[>..]=[];

reusable[] var pool_blot_check_core__SelectedUse:blot_check_core::SelectedUse[>..]=[];

reusable[] var pool_blot_check_core__DictionarySelection:blot_check_core::DictionarySelection[>..]=[];

reusable[] var pool_blot_check_core__DictionaryUse:blot_check_core::DictionaryUse[>..]=[];

reusable[] var pool_blot_check_core__Primitive:blot_check_core::Primitive[>..]=[];

reusable[] var pool_blot_check_core__LoopInfo:blot_check_core::LoopInfo[>..]=[];

reusable[] var pool_blot_check_core__LoopCarry:blot_check_core::LoopCarry[>..]=[];

reusable[] var pool_blot_check_core__ResolverInfo:blot_check_core::ResolverInfo[>..]=[];

reusable[] var pool_blot_check_core__OperationValue:blot_check_core::OperationValue[>..]=[];

reusable[] var pool_blot_check_core__HandleEffects:blot_check_core::HandleEffects[>..]=[];

reusable[] var pool_blot_check_core__Diagnostic:blot_check_core::Diagnostic[>..]=[];

reusable[] var pool_blot_check_parameter_patterns__Node:blot_check_parameter_patterns::Node[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__Binding:blot_reuse_principal_interface::Binding[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__Nominal:blot_reuse_principal_interface::Nominal[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__Constructor:blot_reuse_principal_interface::Constructor[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__EffectFamily:blot_reuse_principal_interface::EffectFamily[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__EffectTemplate:blot_reuse_principal_interface::EffectTemplate[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__Associated:blot_reuse_principal_interface::Associated[>..]=[];

reusable[] var pool_blot_reuse_principal_interface__Contract:blot_reuse_principal_interface::Contract[>..]=[];

reusable[] var pool_blot_reuse_frozen_dependency__ImportResolution:blot_reuse_frozen_dependency::ImportResolution[>..]=[];

reusable[] var pool_blot_reuse_frozen_dependency__Export:blot_reuse_frozen_dependency::Export[>..]=[];

reusable[] var pool_blot_reuse_frozen_dependency__Fixity:blot_reuse_frozen_dependency::Fixity[>..]=[];

reusable[] var pool_blot_reuse_frozen_dependency__Symbol:blot_reuse_frozen_dependency::Symbol[>..]=[];

reusable[] var pool_blot_reuse_frozen_dependency__Module:blot_reuse_frozen_dependency::Module[>..]=[];

fn valid(self:const Owner&)->bool {return self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation;}
fn init()->Owner,Error {if leases.len>=0xffffffff {return Owner {},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=leases.alloc_index(Lease {generation:generation,live:true});return Owner {(at+1) as u32,generation},Error.none;}
fn remember(self:Owner&,value:Run)->Error {assert(valid(self));if links.len>=0xffffffff {return Error.out_of_memory;}let head=leases[self.lease-1].head;let at=links.alloc_index(Link {value,head});leases[self.lease-1].head=(at+1) as u32;return Error.none;}
fn deinit(self:Owner&) {if self.lease==0 {return;}assert(valid(self));let owner=self.lease-1;var next=leases[owner].head;while next!=0 {let at=next-1;let link=links[at];next=link.next;match link.value {

Run.run_u32 run=>{pool_u32.free_slice(run.values);},

Run.run_blot_check_numeric_proof_terms__Kind run=>{pool_blot_check_numeric_proof_terms__Kind.free_slice(run.values);},

Run.run_blot_check_numeric_proof_terms__Term run=>{pool_blot_check_numeric_proof_terms__Term.free_slice(run.values);},

Run.run_blot_check_numeric_proof_contracts__Requirement run=>{pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run.values);},

Run.run_blot_check_numeric_proof_headers__Named run=>{pool_blot_check_numeric_proof_headers__Named.free_slice(run.values);},

Run.run_blot_check_capability_contracts__Term run=>{pool_blot_check_capability_contracts__Term.free_slice(run.values);},

Run.run_blot_check_capability_contracts__Binding run=>{pool_blot_check_capability_contracts__Binding.free_slice(run.values);},

Run.run_blot_check_core__FieldName run=>{pool_blot_check_core__FieldName.free_slice(run.values);},

Run.run_blot_check_core__RuntimeName run=>{pool_blot_check_core__RuntimeName.free_slice(run.values);},

Run.run_blot_check_core__DeclarationDependencies run=>{pool_blot_check_core__DeclarationDependencies.free_slice(run.values);},

Run.run_blot_check_core__BindingRef run=>{pool_blot_check_core__BindingRef.free_slice(run.values);},

Run.run_blot_check_core__DependencyMember run=>{pool_blot_check_core__DependencyMember.free_slice(run.values);},

Run.run_blot_check_core__ErasedDeclarationReference run=>{pool_blot_check_core__ErasedDeclarationReference.free_slice(run.values);},

Run.run_blot_check_core__RequestLoopInfo run=>{pool_blot_check_core__RequestLoopInfo.free_slice(run.values);},

Run.run_blot_check_core__RequestArm run=>{pool_blot_check_core__RequestArm.free_slice(run.values);},

Run.run_blot_check_types__Node run=>{pool_blot_check_types__Node.free_slice(run.values);},

Run.run_blot_check_effects__Row run=>{pool_blot_check_effects__Row.free_slice(run.values);},

Run.run_blot_check_types__Operation run=>{pool_blot_check_types__Operation.free_slice(run.values);},

Run.run_blot_check_types__QuantifierGoals run=>{pool_blot_check_types__QuantifierGoals.free_slice(run.values);},

Run.run_blot_check_types__Obligation run=>{pool_blot_check_types__Obligation.free_slice(run.values);},

Run.run_blot_check_core__Node run=>{pool_blot_check_core__Node.free_slice(run.values);},

Run.run_blot_parse_ast__Span run=>{pool_blot_parse_ast__Span.free_slice(run.values);},

Run.run_blot_check_core__Binding run=>{pool_blot_check_core__Binding.free_slice(run.values);},

Run.run_blot_check_core__Body run=>{pool_blot_check_core__Body.free_slice(run.values);},

Run.run_blot_check_core__Parameter run=>{pool_blot_check_core__Parameter.free_slice(run.values);},

Run.run_blot_check_core__CallInfo run=>{pool_blot_check_core__CallInfo.free_slice(run.values);},

Run.run_blot_check_core__Merge run=>{pool_blot_check_core__Merge.free_slice(run.values);},

Run.run_blot_check_core__List run=>{pool_blot_check_core__List.free_slice(run.values);},

Run.run_u8 run=>{pool_u8.free_slice(run.values);},

Run.run_blot_check_core__Obligation run=>{pool_blot_check_core__Obligation.free_slice(run.values);},

Run.run_blot_check_core__Nominal run=>{pool_blot_check_core__Nominal.free_slice(run.values);},

Run.run_blot_check_core__OperationName run=>{pool_blot_check_core__OperationName.free_slice(run.values);},

Run.run_blot_check_core__Constructor run=>{pool_blot_check_core__Constructor.free_slice(run.values);},

Run.run_blot_check_core__Projection run=>{pool_blot_check_core__Projection.free_slice(run.values);},

Run.run_blot_check_core__ProjectionVariant run=>{pool_blot_check_core__ProjectionVariant.free_slice(run.values);},

Run.run_blot_check_core__Pattern run=>{pool_blot_check_core__Pattern.free_slice(run.values);},

Run.run_blot_check_core__PatternRow run=>{pool_blot_check_core__PatternRow.free_slice(run.values);},

Run.run_blot_check_core__MatchArm run=>{pool_blot_check_core__MatchArm.free_slice(run.values);},

Run.run_blot_check_core__MatchInfo run=>{pool_blot_check_core__MatchInfo.free_slice(run.values);},

Run.run_blot_check_core__UpdateInfo run=>{pool_blot_check_core__UpdateInfo.free_slice(run.values);},

Run.run_blot_check_core__UpdateStep run=>{pool_blot_check_core__UpdateStep.free_slice(run.values);},

Run.run_blot_check_core__ClosureInfo run=>{pool_blot_check_core__ClosureInfo.free_slice(run.values);},

Run.run_blot_check_core__Associated run=>{pool_blot_check_core__Associated.free_slice(run.values);},

Run.run_blot_check_core__Contract run=>{pool_blot_check_core__Contract.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__ContractMember run=>{pool_blot_reuse_principal_interface__ContractMember.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__Implementation run=>{pool_blot_reuse_principal_interface__Implementation.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__ImplementationMember run=>{pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__MemberTemplate run=>{pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__SelectedProof run=>{pool_blot_reuse_principal_interface__SelectedProof.free_slice(run.values);},

Run.run_blot_check_core__SelectedUse run=>{pool_blot_check_core__SelectedUse.free_slice(run.values);},

Run.run_blot_check_core__DictionarySelection run=>{pool_blot_check_core__DictionarySelection.free_slice(run.values);},

Run.run_blot_check_core__DictionaryUse run=>{pool_blot_check_core__DictionaryUse.free_slice(run.values);},

Run.run_blot_check_core__Primitive run=>{pool_blot_check_core__Primitive.free_slice(run.values);},

Run.run_blot_check_core__LoopInfo run=>{pool_blot_check_core__LoopInfo.free_slice(run.values);},

Run.run_blot_check_core__LoopCarry run=>{pool_blot_check_core__LoopCarry.free_slice(run.values);},

Run.run_blot_check_core__ResolverInfo run=>{pool_blot_check_core__ResolverInfo.free_slice(run.values);},

Run.run_blot_check_core__OperationValue run=>{pool_blot_check_core__OperationValue.free_slice(run.values);},

Run.run_blot_check_core__HandleEffects run=>{pool_blot_check_core__HandleEffects.free_slice(run.values);},

Run.run_blot_check_core__Diagnostic run=>{pool_blot_check_core__Diagnostic.free_slice(run.values);},

Run.run_blot_check_parameter_patterns__Node run=>{pool_blot_check_parameter_patterns__Node.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__Binding run=>{pool_blot_reuse_principal_interface__Binding.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__Nominal run=>{pool_blot_reuse_principal_interface__Nominal.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__Constructor run=>{pool_blot_reuse_principal_interface__Constructor.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__EffectFamily run=>{pool_blot_reuse_principal_interface__EffectFamily.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__EffectTemplate run=>{pool_blot_reuse_principal_interface__EffectTemplate.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__Associated run=>{pool_blot_reuse_principal_interface__Associated.free_slice(run.values);},

Run.run_blot_reuse_principal_interface__Contract run=>{pool_blot_reuse_principal_interface__Contract.free_slice(run.values);},

Run.run_blot_reuse_frozen_dependency__ImportResolution run=>{pool_blot_reuse_frozen_dependency__ImportResolution.free_slice(run.values);},

Run.run_blot_reuse_frozen_dependency__Export run=>{pool_blot_reuse_frozen_dependency__Export.free_slice(run.values);},

Run.run_blot_reuse_frozen_dependency__Fixity run=>{pool_blot_reuse_frozen_dependency__Fixity.free_slice(run.values);},

Run.run_blot_reuse_frozen_dependency__Symbol run=>{pool_blot_reuse_frozen_dependency__Symbol.free_slice(run.values);},

Run.run_blot_reuse_frozen_dependency__Module run=>{pool_blot_reuse_frozen_dependency__Module.free_slice(run.values);},

}links.free(at);}leases[owner].live=false;self=Owner {};leases.free(owner);}
fn deinit<T>(self:Owned<T>&) {self.owner.deinit();self.value=default<T>();}
fn adopt(self:Owner&,source:Owner&)->Error {
 assert(valid(self)&&valid(source));if self.lease==source.lease {return Error.invalid_artifact;}
 let at=source.lease-1;let head=leases[at].head;if head!=0 {var tail=head;while links[tail-1].next!=0 {tail=links[tail-1].next;}links[tail-1].next=leases[self.lease-1].head;leases[self.lease-1].head=head;}
 leases[at].live=false;source=Owner {};leases.free(at);return Error.none;
}
fn alloc<T>(self:Owner&,length:i64)->T[:],Error {return allocate(self,default<T>(),length);}
fn copy<T>(self:Owner&,values:const T[:])->T[:],Error {let result,error=self.alloc<T>(values.len);if error!=Error.none {return [],error;}for value,index in values {result[index]=value;}return result,Error.none;}

fn allocate(self:Owner&,sample:u32,length:i64)->u32[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_u32.alloc_slice(length);let error=remember(self,Run.run_u32 {run});if error!=Error.none {pool_u32.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const u32[:])->u32[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_u32 run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const u32[:])->u32[:],Error {
 let result,error=self.alloc<u32>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_numeric_proof_terms::Kind,length:i64)->blot_check_numeric_proof_terms::Kind[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_numeric_proof_terms__Kind.alloc_slice(length);let error=remember(self,Run.run_blot_check_numeric_proof_terms__Kind {run});if error!=Error.none {pool_blot_check_numeric_proof_terms__Kind.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_numeric_proof_terms::Kind[:])->blot_check_numeric_proof_terms::Kind[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_terms__Kind run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_numeric_proof_terms::Kind[:])->blot_check_numeric_proof_terms::Kind[:],Error {
 let result,error=self.alloc<blot_check_numeric_proof_terms::Kind>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_numeric_proof_terms::Term,length:i64)->blot_check_numeric_proof_terms::Term[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_numeric_proof_terms__Term.alloc_slice(length);let error=remember(self,Run.run_blot_check_numeric_proof_terms__Term {run});if error!=Error.none {pool_blot_check_numeric_proof_terms__Term.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_terms__Term run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:],Error {
 let result,error=self.alloc<blot_check_numeric_proof_terms::Term>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_numeric_proof_contracts::Requirement,length:i64)->blot_check_numeric_proof_contracts::Requirement[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_numeric_proof_contracts__Requirement.alloc_slice(length);let error=remember(self,Run.run_blot_check_numeric_proof_contracts__Requirement {run});if error!=Error.none {pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_numeric_proof_contracts::Requirement[:])->blot_check_numeric_proof_contracts::Requirement[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_contracts__Requirement run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_numeric_proof_contracts::Requirement[:])->blot_check_numeric_proof_contracts::Requirement[:],Error {
 let result,error=self.alloc<blot_check_numeric_proof_contracts::Requirement>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_numeric_proof_headers::Named,length:i64)->blot_check_numeric_proof_headers::Named[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_numeric_proof_headers__Named.alloc_slice(length);let error=remember(self,Run.run_blot_check_numeric_proof_headers__Named {run});if error!=Error.none {pool_blot_check_numeric_proof_headers__Named.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_numeric_proof_headers::Named[:])->blot_check_numeric_proof_headers::Named[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_headers__Named run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_numeric_proof_headers::Named[:])->blot_check_numeric_proof_headers::Named[:],Error {
 let result,error=self.alloc<blot_check_numeric_proof_headers::Named>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_capability_contracts::Term,length:i64)->blot_check_capability_contracts::Term[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_capability_contracts__Term.alloc_slice(length);let error=remember(self,Run.run_blot_check_capability_contracts__Term {run});if error!=Error.none {pool_blot_check_capability_contracts__Term.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_capability_contracts__Term run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:],Error {
 let result,error=self.alloc<blot_check_capability_contracts::Term>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_capability_contracts::Binding,length:i64)->blot_check_capability_contracts::Binding[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_capability_contracts__Binding.alloc_slice(length);let error=remember(self,Run.run_blot_check_capability_contracts__Binding {run});if error!=Error.none {pool_blot_check_capability_contracts__Binding.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_capability_contracts__Binding run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:],Error {
 let result,error=self.alloc<blot_check_capability_contracts::Binding>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::FieldName,length:i64)->blot_check_core::FieldName[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__FieldName.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__FieldName {run});if error!=Error.none {pool_blot_check_core__FieldName.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::FieldName[:])->blot_check_core::FieldName[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__FieldName run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::FieldName[:])->blot_check_core::FieldName[:],Error {
 let result,error=self.alloc<blot_check_core::FieldName>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::RuntimeName,length:i64)->blot_check_core::RuntimeName[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__RuntimeName.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__RuntimeName {run});if error!=Error.none {pool_blot_check_core__RuntimeName.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::RuntimeName[:])->blot_check_core::RuntimeName[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__RuntimeName run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::RuntimeName[:])->blot_check_core::RuntimeName[:],Error {
 let result,error=self.alloc<blot_check_core::RuntimeName>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::DeclarationDependencies,length:i64)->blot_check_core::DeclarationDependencies[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__DeclarationDependencies.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__DeclarationDependencies {run});if error!=Error.none {pool_blot_check_core__DeclarationDependencies.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::DeclarationDependencies[:])->blot_check_core::DeclarationDependencies[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DeclarationDependencies run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::DeclarationDependencies[:])->blot_check_core::DeclarationDependencies[:],Error {
 let result,error=self.alloc<blot_check_core::DeclarationDependencies>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::BindingRef,length:i64)->blot_check_core::BindingRef[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__BindingRef.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__BindingRef {run});if error!=Error.none {pool_blot_check_core__BindingRef.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::BindingRef[:])->blot_check_core::BindingRef[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__BindingRef run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::BindingRef[:])->blot_check_core::BindingRef[:],Error {
 let result,error=self.alloc<blot_check_core::BindingRef>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::DependencyMember,length:i64)->blot_check_core::DependencyMember[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__DependencyMember.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__DependencyMember {run});if error!=Error.none {pool_blot_check_core__DependencyMember.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::DependencyMember[:])->blot_check_core::DependencyMember[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DependencyMember run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::DependencyMember[:])->blot_check_core::DependencyMember[:],Error {
 let result,error=self.alloc<blot_check_core::DependencyMember>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::ErasedDeclarationReference,length:i64)->blot_check_core::ErasedDeclarationReference[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__ErasedDeclarationReference.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__ErasedDeclarationReference {run});if error!=Error.none {pool_blot_check_core__ErasedDeclarationReference.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::ErasedDeclarationReference[:])->blot_check_core::ErasedDeclarationReference[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ErasedDeclarationReference run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::ErasedDeclarationReference[:])->blot_check_core::ErasedDeclarationReference[:],Error {
 let result,error=self.alloc<blot_check_core::ErasedDeclarationReference>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::RequestLoopInfo,length:i64)->blot_check_core::RequestLoopInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__RequestLoopInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__RequestLoopInfo {run});if error!=Error.none {pool_blot_check_core__RequestLoopInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::RequestLoopInfo[:])->blot_check_core::RequestLoopInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__RequestLoopInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::RequestLoopInfo[:])->blot_check_core::RequestLoopInfo[:],Error {
 let result,error=self.alloc<blot_check_core::RequestLoopInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::RequestArm,length:i64)->blot_check_core::RequestArm[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__RequestArm.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__RequestArm {run});if error!=Error.none {pool_blot_check_core__RequestArm.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::RequestArm[:])->blot_check_core::RequestArm[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__RequestArm run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::RequestArm[:])->blot_check_core::RequestArm[:],Error {
 let result,error=self.alloc<blot_check_core::RequestArm>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_types::Node,length:i64)->blot_check_types::Node[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_types__Node.alloc_slice(length);let error=remember(self,Run.run_blot_check_types__Node {run});if error!=Error.none {pool_blot_check_types__Node.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_types::Node[:])->blot_check_types::Node[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__Node run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_types::Node[:])->blot_check_types::Node[:],Error {
 let result,error=self.alloc<blot_check_types::Node>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_effects::Row,length:i64)->blot_check_effects::Row[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_effects__Row.alloc_slice(length);let error=remember(self,Run.run_blot_check_effects__Row {run});if error!=Error.none {pool_blot_check_effects__Row.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_effects::Row[:])->blot_check_effects::Row[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_effects__Row run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_effects::Row[:])->blot_check_effects::Row[:],Error {
 let result,error=self.alloc<blot_check_effects::Row>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_types::Operation,length:i64)->blot_check_types::Operation[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_types__Operation.alloc_slice(length);let error=remember(self,Run.run_blot_check_types__Operation {run});if error!=Error.none {pool_blot_check_types__Operation.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_types::Operation[:])->blot_check_types::Operation[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__Operation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_types::Operation[:])->blot_check_types::Operation[:],Error {
 let result,error=self.alloc<blot_check_types::Operation>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_types::QuantifierGoals,length:i64)->blot_check_types::QuantifierGoals[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_types__QuantifierGoals.alloc_slice(length);let error=remember(self,Run.run_blot_check_types__QuantifierGoals {run});if error!=Error.none {pool_blot_check_types__QuantifierGoals.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_types::QuantifierGoals[:])->blot_check_types::QuantifierGoals[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__QuantifierGoals run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_types::QuantifierGoals[:])->blot_check_types::QuantifierGoals[:],Error {
 let result,error=self.alloc<blot_check_types::QuantifierGoals>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_types::Obligation,length:i64)->blot_check_types::Obligation[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_types__Obligation.alloc_slice(length);let error=remember(self,Run.run_blot_check_types__Obligation {run});if error!=Error.none {pool_blot_check_types__Obligation.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__Obligation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:],Error {
 let result,error=self.alloc<blot_check_types::Obligation>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Node,length:i64)->blot_check_core::Node[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Node.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Node {run});if error!=Error.none {pool_blot_check_core__Node.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Node[:])->blot_check_core::Node[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Node run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Node[:])->blot_check_core::Node[:],Error {
 let result,error=self.alloc<blot_check_core::Node>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_parse_ast::Span,length:i64)->blot_parse_ast::Span[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_parse_ast__Span.alloc_slice(length);let error=remember(self,Run.run_blot_parse_ast__Span {run});if error!=Error.none {pool_blot_parse_ast__Span.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_parse_ast::Span[:])->blot_parse_ast::Span[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_parse_ast__Span run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_parse_ast::Span[:])->blot_parse_ast::Span[:],Error {
 let result,error=self.alloc<blot_parse_ast::Span>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Binding,length:i64)->blot_check_core::Binding[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Binding.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Binding {run});if error!=Error.none {pool_blot_check_core__Binding.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Binding[:])->blot_check_core::Binding[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Binding run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Binding[:])->blot_check_core::Binding[:],Error {
 let result,error=self.alloc<blot_check_core::Binding>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Body,length:i64)->blot_check_core::Body[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Body.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Body {run});if error!=Error.none {pool_blot_check_core__Body.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Body[:])->blot_check_core::Body[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Body run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Body[:])->blot_check_core::Body[:],Error {
 let result,error=self.alloc<blot_check_core::Body>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Parameter,length:i64)->blot_check_core::Parameter[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Parameter.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Parameter {run});if error!=Error.none {pool_blot_check_core__Parameter.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Parameter[:])->blot_check_core::Parameter[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Parameter run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Parameter[:])->blot_check_core::Parameter[:],Error {
 let result,error=self.alloc<blot_check_core::Parameter>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::CallInfo,length:i64)->blot_check_core::CallInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__CallInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__CallInfo {run});if error!=Error.none {pool_blot_check_core__CallInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::CallInfo[:])->blot_check_core::CallInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__CallInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::CallInfo[:])->blot_check_core::CallInfo[:],Error {
 let result,error=self.alloc<blot_check_core::CallInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Merge,length:i64)->blot_check_core::Merge[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Merge.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Merge {run});if error!=Error.none {pool_blot_check_core__Merge.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Merge[:])->blot_check_core::Merge[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Merge run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Merge[:])->blot_check_core::Merge[:],Error {
 let result,error=self.alloc<blot_check_core::Merge>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::List,length:i64)->blot_check_core::List[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__List.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__List {run});if error!=Error.none {pool_blot_check_core__List.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::List[:])->blot_check_core::List[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__List run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::List[:])->blot_check_core::List[:],Error {
 let result,error=self.alloc<blot_check_core::List>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:u8,length:i64)->u8[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_u8.alloc_slice(length);let error=remember(self,Run.run_u8 {run});if error!=Error.none {pool_u8.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const u8[:])->u8[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_u8 run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const u8[:])->u8[:],Error {
 let result,error=self.alloc<u8>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Obligation,length:i64)->blot_check_core::Obligation[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Obligation.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Obligation {run});if error!=Error.none {pool_blot_check_core__Obligation.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Obligation[:])->blot_check_core::Obligation[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Obligation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Obligation[:])->blot_check_core::Obligation[:],Error {
 let result,error=self.alloc<blot_check_core::Obligation>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Nominal,length:i64)->blot_check_core::Nominal[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Nominal.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Nominal {run});if error!=Error.none {pool_blot_check_core__Nominal.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Nominal[:])->blot_check_core::Nominal[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Nominal run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Nominal[:])->blot_check_core::Nominal[:],Error {
 let result,error=self.alloc<blot_check_core::Nominal>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::OperationName,length:i64)->blot_check_core::OperationName[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__OperationName.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__OperationName {run});if error!=Error.none {pool_blot_check_core__OperationName.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::OperationName[:])->blot_check_core::OperationName[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__OperationName run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::OperationName[:])->blot_check_core::OperationName[:],Error {
 let result,error=self.alloc<blot_check_core::OperationName>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Constructor,length:i64)->blot_check_core::Constructor[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Constructor.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Constructor {run});if error!=Error.none {pool_blot_check_core__Constructor.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Constructor[:])->blot_check_core::Constructor[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Constructor run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Constructor[:])->blot_check_core::Constructor[:],Error {
 let result,error=self.alloc<blot_check_core::Constructor>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Projection,length:i64)->blot_check_core::Projection[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Projection.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Projection {run});if error!=Error.none {pool_blot_check_core__Projection.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Projection[:])->blot_check_core::Projection[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Projection run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Projection[:])->blot_check_core::Projection[:],Error {
 let result,error=self.alloc<blot_check_core::Projection>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::ProjectionVariant,length:i64)->blot_check_core::ProjectionVariant[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__ProjectionVariant.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__ProjectionVariant {run});if error!=Error.none {pool_blot_check_core__ProjectionVariant.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::ProjectionVariant[:])->blot_check_core::ProjectionVariant[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ProjectionVariant run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::ProjectionVariant[:])->blot_check_core::ProjectionVariant[:],Error {
 let result,error=self.alloc<blot_check_core::ProjectionVariant>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Pattern,length:i64)->blot_check_core::Pattern[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Pattern.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Pattern {run});if error!=Error.none {pool_blot_check_core__Pattern.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Pattern[:])->blot_check_core::Pattern[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Pattern run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Pattern[:])->blot_check_core::Pattern[:],Error {
 let result,error=self.alloc<blot_check_core::Pattern>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::PatternRow,length:i64)->blot_check_core::PatternRow[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__PatternRow.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__PatternRow {run});if error!=Error.none {pool_blot_check_core__PatternRow.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::PatternRow[:])->blot_check_core::PatternRow[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__PatternRow run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::PatternRow[:])->blot_check_core::PatternRow[:],Error {
 let result,error=self.alloc<blot_check_core::PatternRow>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::MatchArm,length:i64)->blot_check_core::MatchArm[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__MatchArm.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__MatchArm {run});if error!=Error.none {pool_blot_check_core__MatchArm.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::MatchArm[:])->blot_check_core::MatchArm[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__MatchArm run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::MatchArm[:])->blot_check_core::MatchArm[:],Error {
 let result,error=self.alloc<blot_check_core::MatchArm>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::MatchInfo,length:i64)->blot_check_core::MatchInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__MatchInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__MatchInfo {run});if error!=Error.none {pool_blot_check_core__MatchInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::MatchInfo[:])->blot_check_core::MatchInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__MatchInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::MatchInfo[:])->blot_check_core::MatchInfo[:],Error {
 let result,error=self.alloc<blot_check_core::MatchInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::UpdateInfo,length:i64)->blot_check_core::UpdateInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__UpdateInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__UpdateInfo {run});if error!=Error.none {pool_blot_check_core__UpdateInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::UpdateInfo[:])->blot_check_core::UpdateInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__UpdateInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::UpdateInfo[:])->blot_check_core::UpdateInfo[:],Error {
 let result,error=self.alloc<blot_check_core::UpdateInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::UpdateStep,length:i64)->blot_check_core::UpdateStep[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__UpdateStep.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__UpdateStep {run});if error!=Error.none {pool_blot_check_core__UpdateStep.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::UpdateStep[:])->blot_check_core::UpdateStep[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__UpdateStep run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::UpdateStep[:])->blot_check_core::UpdateStep[:],Error {
 let result,error=self.alloc<blot_check_core::UpdateStep>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::ClosureInfo,length:i64)->blot_check_core::ClosureInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__ClosureInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__ClosureInfo {run});if error!=Error.none {pool_blot_check_core__ClosureInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::ClosureInfo[:])->blot_check_core::ClosureInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ClosureInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::ClosureInfo[:])->blot_check_core::ClosureInfo[:],Error {
 let result,error=self.alloc<blot_check_core::ClosureInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Associated,length:i64)->blot_check_core::Associated[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Associated.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Associated {run});if error!=Error.none {pool_blot_check_core__Associated.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Associated[:])->blot_check_core::Associated[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Associated run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Associated[:])->blot_check_core::Associated[:],Error {
 let result,error=self.alloc<blot_check_core::Associated>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Contract,length:i64)->blot_check_core::Contract[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Contract.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Contract {run});if error!=Error.none {pool_blot_check_core__Contract.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Contract[:])->blot_check_core::Contract[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Contract run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Contract[:])->blot_check_core::Contract[:],Error {
 let result,error=self.alloc<blot_check_core::Contract>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::ContractMember,length:i64)->blot_reuse_principal_interface::ContractMember[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__ContractMember.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__ContractMember {run});if error!=Error.none {pool_blot_reuse_principal_interface__ContractMember.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::ContractMember[:])->blot_reuse_principal_interface::ContractMember[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__ContractMember run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::ContractMember[:])->blot_reuse_principal_interface::ContractMember[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::ContractMember>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::Implementation,length:i64)->blot_reuse_principal_interface::Implementation[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__Implementation.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__Implementation {run});if error!=Error.none {pool_blot_reuse_principal_interface__Implementation.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::Implementation[:])->blot_reuse_principal_interface::Implementation[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Implementation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::Implementation[:])->blot_reuse_principal_interface::Implementation[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::Implementation>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::ImplementationMember,length:i64)->blot_reuse_principal_interface::ImplementationMember[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__ImplementationMember.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__ImplementationMember {run});if error!=Error.none {pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::ImplementationMember[:])->blot_reuse_principal_interface::ImplementationMember[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__ImplementationMember run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::ImplementationMember[:])->blot_reuse_principal_interface::ImplementationMember[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::ImplementationMember>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::MemberTemplate,length:i64)->blot_reuse_principal_interface::MemberTemplate[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__MemberTemplate.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__MemberTemplate {run});if error!=Error.none {pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__MemberTemplate run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::MemberTemplate>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::SelectedProof,length:i64)->blot_reuse_principal_interface::SelectedProof[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__SelectedProof.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__SelectedProof {run});if error!=Error.none {pool_blot_reuse_principal_interface__SelectedProof.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__SelectedProof run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::SelectedProof>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::SelectedUse,length:i64)->blot_check_core::SelectedUse[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__SelectedUse.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__SelectedUse {run});if error!=Error.none {pool_blot_check_core__SelectedUse.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::SelectedUse[:])->blot_check_core::SelectedUse[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__SelectedUse run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::SelectedUse[:])->blot_check_core::SelectedUse[:],Error {
 let result,error=self.alloc<blot_check_core::SelectedUse>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::DictionarySelection,length:i64)->blot_check_core::DictionarySelection[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__DictionarySelection.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__DictionarySelection {run});if error!=Error.none {pool_blot_check_core__DictionarySelection.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::DictionarySelection[:])->blot_check_core::DictionarySelection[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DictionarySelection run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::DictionarySelection[:])->blot_check_core::DictionarySelection[:],Error {
 let result,error=self.alloc<blot_check_core::DictionarySelection>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::DictionaryUse,length:i64)->blot_check_core::DictionaryUse[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__DictionaryUse.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__DictionaryUse {run});if error!=Error.none {pool_blot_check_core__DictionaryUse.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::DictionaryUse[:])->blot_check_core::DictionaryUse[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DictionaryUse run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::DictionaryUse[:])->blot_check_core::DictionaryUse[:],Error {
 let result,error=self.alloc<blot_check_core::DictionaryUse>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Primitive,length:i64)->blot_check_core::Primitive[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Primitive.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Primitive {run});if error!=Error.none {pool_blot_check_core__Primitive.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Primitive[:])->blot_check_core::Primitive[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Primitive run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Primitive[:])->blot_check_core::Primitive[:],Error {
 let result,error=self.alloc<blot_check_core::Primitive>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::LoopInfo,length:i64)->blot_check_core::LoopInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__LoopInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__LoopInfo {run});if error!=Error.none {pool_blot_check_core__LoopInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::LoopInfo[:])->blot_check_core::LoopInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__LoopInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::LoopInfo[:])->blot_check_core::LoopInfo[:],Error {
 let result,error=self.alloc<blot_check_core::LoopInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::LoopCarry,length:i64)->blot_check_core::LoopCarry[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__LoopCarry.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__LoopCarry {run});if error!=Error.none {pool_blot_check_core__LoopCarry.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::LoopCarry[:])->blot_check_core::LoopCarry[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__LoopCarry run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::LoopCarry[:])->blot_check_core::LoopCarry[:],Error {
 let result,error=self.alloc<blot_check_core::LoopCarry>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::ResolverInfo,length:i64)->blot_check_core::ResolverInfo[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__ResolverInfo.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__ResolverInfo {run});if error!=Error.none {pool_blot_check_core__ResolverInfo.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::ResolverInfo[:])->blot_check_core::ResolverInfo[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ResolverInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::ResolverInfo[:])->blot_check_core::ResolverInfo[:],Error {
 let result,error=self.alloc<blot_check_core::ResolverInfo>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::OperationValue,length:i64)->blot_check_core::OperationValue[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__OperationValue.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__OperationValue {run});if error!=Error.none {pool_blot_check_core__OperationValue.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::OperationValue[:])->blot_check_core::OperationValue[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__OperationValue run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::OperationValue[:])->blot_check_core::OperationValue[:],Error {
 let result,error=self.alloc<blot_check_core::OperationValue>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::HandleEffects,length:i64)->blot_check_core::HandleEffects[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__HandleEffects.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__HandleEffects {run});if error!=Error.none {pool_blot_check_core__HandleEffects.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::HandleEffects[:])->blot_check_core::HandleEffects[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__HandleEffects run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::HandleEffects[:])->blot_check_core::HandleEffects[:],Error {
 let result,error=self.alloc<blot_check_core::HandleEffects>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_core::Diagnostic,length:i64)->blot_check_core::Diagnostic[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_core__Diagnostic.alloc_slice(length);let error=remember(self,Run.run_blot_check_core__Diagnostic {run});if error!=Error.none {pool_blot_check_core__Diagnostic.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_core::Diagnostic[:])->blot_check_core::Diagnostic[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Diagnostic run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_core::Diagnostic[:])->blot_check_core::Diagnostic[:],Error {
 let result,error=self.alloc<blot_check_core::Diagnostic>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_check_parameter_patterns::Node,length:i64)->blot_check_parameter_patterns::Node[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_check_parameter_patterns__Node.alloc_slice(length);let error=remember(self,Run.run_blot_check_parameter_patterns__Node {run});if error!=Error.none {pool_blot_check_parameter_patterns__Node.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_check_parameter_patterns::Node[:])->blot_check_parameter_patterns::Node[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_parameter_patterns__Node run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_check_parameter_patterns::Node[:])->blot_check_parameter_patterns::Node[:],Error {
 let result,error=self.alloc<blot_check_parameter_patterns::Node>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::Binding,length:i64)->blot_reuse_principal_interface::Binding[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__Binding.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__Binding {run});if error!=Error.none {pool_blot_reuse_principal_interface__Binding.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::Binding[:])->blot_reuse_principal_interface::Binding[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Binding run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::Binding[:])->blot_reuse_principal_interface::Binding[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::Binding>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::Nominal,length:i64)->blot_reuse_principal_interface::Nominal[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__Nominal.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__Nominal {run});if error!=Error.none {pool_blot_reuse_principal_interface__Nominal.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::Nominal[:])->blot_reuse_principal_interface::Nominal[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Nominal run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::Nominal[:])->blot_reuse_principal_interface::Nominal[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::Nominal>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::Constructor,length:i64)->blot_reuse_principal_interface::Constructor[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__Constructor.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__Constructor {run});if error!=Error.none {pool_blot_reuse_principal_interface__Constructor.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::Constructor[:])->blot_reuse_principal_interface::Constructor[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Constructor run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::Constructor[:])->blot_reuse_principal_interface::Constructor[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::Constructor>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::EffectFamily,length:i64)->blot_reuse_principal_interface::EffectFamily[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__EffectFamily.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__EffectFamily {run});if error!=Error.none {pool_blot_reuse_principal_interface__EffectFamily.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::EffectFamily[:])->blot_reuse_principal_interface::EffectFamily[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__EffectFamily run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::EffectFamily[:])->blot_reuse_principal_interface::EffectFamily[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::EffectFamily>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::EffectTemplate,length:i64)->blot_reuse_principal_interface::EffectTemplate[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__EffectTemplate.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__EffectTemplate {run});if error!=Error.none {pool_blot_reuse_principal_interface__EffectTemplate.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::EffectTemplate[:])->blot_reuse_principal_interface::EffectTemplate[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__EffectTemplate run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::EffectTemplate[:])->blot_reuse_principal_interface::EffectTemplate[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::EffectTemplate>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::Associated,length:i64)->blot_reuse_principal_interface::Associated[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__Associated.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__Associated {run});if error!=Error.none {pool_blot_reuse_principal_interface__Associated.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::Associated[:])->blot_reuse_principal_interface::Associated[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Associated run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::Associated[:])->blot_reuse_principal_interface::Associated[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::Associated>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_principal_interface::Contract,length:i64)->blot_reuse_principal_interface::Contract[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_principal_interface__Contract.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_principal_interface__Contract {run});if error!=Error.none {pool_blot_reuse_principal_interface__Contract.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_principal_interface::Contract[:])->blot_reuse_principal_interface::Contract[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Contract run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_principal_interface::Contract[:])->blot_reuse_principal_interface::Contract[:],Error {
 let result,error=self.alloc<blot_reuse_principal_interface::Contract>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_frozen_dependency::ImportResolution,length:i64)->blot_reuse_frozen_dependency::ImportResolution[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_frozen_dependency__ImportResolution.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_frozen_dependency__ImportResolution {run});if error!=Error.none {pool_blot_reuse_frozen_dependency__ImportResolution.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_frozen_dependency::ImportResolution[:])->blot_reuse_frozen_dependency::ImportResolution[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_frozen_dependency__ImportResolution run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_frozen_dependency::ImportResolution[:])->blot_reuse_frozen_dependency::ImportResolution[:],Error {
 let result,error=self.alloc<blot_reuse_frozen_dependency::ImportResolution>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_frozen_dependency::Export,length:i64)->blot_reuse_frozen_dependency::Export[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Export.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_frozen_dependency__Export {run});if error!=Error.none {pool_blot_reuse_frozen_dependency__Export.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_frozen_dependency::Export[:])->blot_reuse_frozen_dependency::Export[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_frozen_dependency__Export run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_frozen_dependency::Export[:])->blot_reuse_frozen_dependency::Export[:],Error {
 let result,error=self.alloc<blot_reuse_frozen_dependency::Export>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_frozen_dependency::Fixity,length:i64)->blot_reuse_frozen_dependency::Fixity[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Fixity.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_frozen_dependency__Fixity {run});if error!=Error.none {pool_blot_reuse_frozen_dependency__Fixity.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_frozen_dependency::Fixity[:])->blot_reuse_frozen_dependency::Fixity[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_frozen_dependency__Fixity run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_frozen_dependency::Fixity[:])->blot_reuse_frozen_dependency::Fixity[:],Error {
 let result,error=self.alloc<blot_reuse_frozen_dependency::Fixity>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_frozen_dependency::Symbol,length:i64)->blot_reuse_frozen_dependency::Symbol[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Symbol.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_frozen_dependency__Symbol {run});if error!=Error.none {pool_blot_reuse_frozen_dependency__Symbol.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_frozen_dependency::Symbol[:])->blot_reuse_frozen_dependency::Symbol[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_frozen_dependency__Symbol run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_frozen_dependency::Symbol[:])->blot_reuse_frozen_dependency::Symbol[:],Error {
 let result,error=self.alloc<blot_reuse_frozen_dependency::Symbol>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn allocate(self:Owner&,sample:blot_reuse_frozen_dependency::Module,length:i64)->blot_reuse_frozen_dependency::Module[:],Error {
 assert(valid(self));if length<0 {return [],Error.invalid_artifact;}if length==0 {return [],Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Module.alloc_slice(length);let error=remember(self,Run.run_blot_reuse_frozen_dependency__Module {run});if error!=Error.none {pool_blot_reuse_frozen_dependency__Module.free_slice(run);return [],error;}return run,Error.none;
}
fn mutable(self:const Owner&,values:const blot_reuse_frozen_dependency::Module[:])->blot_reuse_frozen_dependency::Module[:] {
 assert(valid(self));if values.len==0 {return [];}var next=leases[self.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_frozen_dependency__Module run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self:Owner&,values:const blot_reuse_frozen_dependency::Module[:])->blot_reuse_frozen_dependency::Module[:],Error {
 let result,error=self.alloc<blot_reuse_frozen_dependency::Module>(values.len);if error!=Error.none {return [],error;}
 for value,index in values {let copied,error=cloneValue(self,value);if error!=Error.none {return [],error;}result[index]=copied;}return result,Error.none;
}

fn cloneValue(self:Owner&,value:bool)->bool,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:f32)->f32,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:f64)->f64,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:i16)->i16,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:i32)->i32,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:i64)->i64,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:i8)->i8,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:u16)->u16,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:u32)->u32,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:u64)->u64,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:u8)->u8,Error {return value,Error.none;}

fn cloneValue(self:Owner&,value:u8[32])->u8[32],Error {var result=default<u8[32]>();for item,index in value {let copied,error=cloneValue(self,item);if error!=Error.none {return result,error;}result[index]=copied;}return result,Error.none;}

fn cloneValue(self:Owner&,value:blot_support::Option<blot_check_numeric_proof_terms::Proposition>)->blot_support::Option<blot_check_numeric_proof_terms::Proposition>,Error {if !value.present {return blot_support::none<blot_check_numeric_proof_terms::Proposition>(),Error.none;}let copied,error=cloneValue(self,value.value);if error!=Error.none {return blot_support::none<blot_check_numeric_proof_terms::Proposition>(),error;}return blot_support::some(copied),Error.none;}

fn cloneValue(self:Owner&,value:blot_support::Option<blot_parse_ast::Span>)->blot_support::Option<blot_parse_ast::Span>,Error {if !value.present {return blot_support::none<blot_parse_ast::Span>(),Error.none;}let copied,error=cloneValue(self,value.value);if error!=Error.none {return blot_support::none<blot_parse_ast::Span>(),error;}return blot_support::some(copied),Error.none;}

fn cloneValue(self:Owner&,value:blot_support::Option<blot_reuse_principal_interface::ExternalTarget>)->blot_support::Option<blot_reuse_principal_interface::ExternalTarget>,Error {if !value.present {return blot_support::none<blot_reuse_principal_interface::ExternalTarget>(),Error.none;}let copied,error=cloneValue(self,value.value);if error!=Error.none {return blot_support::none<blot_reuse_principal_interface::ExternalTarget>(),error;}return blot_support::some(copied),Error.none;}

fn cloneValue(self:Owner&,value:blot_check_core::Module)->blot_check_core::Module,Error {

var result=default<blot_check_core::Module>();

{let copied,error=cloneValue(self,value.has_rank_contracts);if error!=Error.none {return result,error;}result.has_rank_contracts=copied;}

{let copied,error=cloneValue(self,value.has_usage_contracts);if error!=Error.none {return result,error;}result.has_usage_contracts=copied;}

{let copied,error=cloneValue(self,value.has_numeric_proofs);if error!=Error.none {return result,error;}result.has_numeric_proofs=copied;}

{let copied,error=cloneValue(self,value.proof_contracts);if error!=Error.none {return result,error;}result.proof_contracts=copied;}

{let copied,error=cloneValue(self,value.capability_contracts);if error!=Error.none {return result,error;}result.capability_contracts=copied;}

{let copied,error=cloneValue(self,value.field_names);if error!=Error.none {return result,error;}result.field_names=copied;}

{let copied,error=cloneValue(self,value.runtime_names);if error!=Error.none {return result,error;}result.runtime_names=copied;}

{let copied,error=cloneValue(self,value.source_names);if error!=Error.none {return result,error;}result.source_names=copied;}

{let copied,error=cloneValue(self,value.declaration_dependencies);if error!=Error.none {return result,error;}result.declaration_dependencies=copied;}

{let copied,error=cloneValue(self,value.dependency_references);if error!=Error.none {return result,error;}result.dependency_references=copied;}

{let copied,error=cloneValue(self,value.dependency_members);if error!=Error.none {return result,error;}result.dependency_members=copied;}

{let copied,error=cloneValue(self,value.erased_declaration_references);if error!=Error.none {return result,error;}result.erased_declaration_references=copied;}

{let copied,error=cloneValue(self,value.request_loops);if error!=Error.none {return result,error;}result.request_loops=copied;}

{let copied,error=cloneValue(self,value.request_arms);if error!=Error.none {return result,error;}result.request_arms=copied;}

{let copied,error=cloneValue(self,value.tag_calls);if error!=Error.none {return result,error;}result.tag_calls=copied;}

{let copied,error=cloneValue(self,value.unit);if error!=Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self,value.types);if error!=Error.none {return result,error;}result.types=copied;}

{let copied,error=cloneValue(self,value.nodes);if error!=Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self,value.spans);if error!=Error.none {return result,error;}result.spans=copied;}

{let copied,error=cloneValue(self,value.extra);if error!=Error.none {return result,error;}result.extra=copied;}

{let copied,error=cloneValue(self,value.bindings);if error!=Error.none {return result,error;}result.bindings=copied;}

{let copied,error=cloneValue(self,value.bodies);if error!=Error.none {return result,error;}result.bodies=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.references);if error!=Error.none {return result,error;}result.references=copied;}

{let copied,error=cloneValue(self,value.calls);if error!=Error.none {return result,error;}result.calls=copied;}

{let copied,error=cloneValue(self,value.merges);if error!=Error.none {return result,error;}result.merges=copied;}

{let copied,error=cloneValue(self,value.merge_ranges);if error!=Error.none {return result,error;}result.merge_ranges=copied;}

{let copied,error=cloneValue(self,value.names);if error!=Error.none {return result,error;}result.names=copied;}

{let copied,error=cloneValue(self,value.obligations);if error!=Error.none {return result,error;}result.obligations=copied;}

{let copied,error=cloneValue(self,value.nominals);if error!=Error.none {return result,error;}result.nominals=copied;}

{let copied,error=cloneValue(self,value.operation_names);if error!=Error.none {return result,error;}result.operation_names=copied;}

{let copied,error=cloneValue(self,value.constructors);if error!=Error.none {return result,error;}result.constructors=copied;}

{let copied,error=cloneValue(self,value.projections);if error!=Error.none {return result,error;}result.projections=copied;}

{let copied,error=cloneValue(self,value.projection_variants);if error!=Error.none {return result,error;}result.projection_variants=copied;}

{let copied,error=cloneValue(self,value.patterns);if error!=Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self,value.pattern_rows);if error!=Error.none {return result,error;}result.pattern_rows=copied;}

{let copied,error=cloneValue(self,value.match_arms);if error!=Error.none {return result,error;}result.match_arms=copied;}

{let copied,error=cloneValue(self,value.matches);if error!=Error.none {return result,error;}result.matches=copied;}

{let copied,error=cloneValue(self,value.updates);if error!=Error.none {return result,error;}result.updates=copied;}

{let copied,error=cloneValue(self,value.update_steps);if error!=Error.none {return result,error;}result.update_steps=copied;}

{let copied,error=cloneValue(self,value.closures);if error!=Error.none {return result,error;}result.closures=copied;}

{let copied,error=cloneValue(self,value.associated);if error!=Error.none {return result,error;}result.associated=copied;}

{let copied,error=cloneValue(self,value.contracts);if error!=Error.none {return result,error;}result.contracts=copied;}

{let copied,error=cloneValue(self,value.contract_members);if error!=Error.none {return result,error;}result.contract_members=copied;}

{let copied,error=cloneValue(self,value.implementations);if error!=Error.none {return result,error;}result.implementations=copied;}

{let copied,error=cloneValue(self,value.implementation_members);if error!=Error.none {return result,error;}result.implementation_members=copied;}

{let copied,error=cloneValue(self,value.member_templates);if error!=Error.none {return result,error;}result.member_templates=copied;}

{let copied,error=cloneValue(self,value.selected_proofs);if error!=Error.none {return result,error;}result.selected_proofs=copied;}

{let copied,error=cloneValue(self,value.selected_members);if error!=Error.none {return result,error;}result.selected_members=copied;}

{let copied,error=cloneValue(self,value.selected_edges);if error!=Error.none {return result,error;}result.selected_edges=copied;}

{let copied,error=cloneValue(self,value.selected_uses);if error!=Error.none {return result,error;}result.selected_uses=copied;}

{let copied,error=cloneValue(self,value.dictionary_selections);if error!=Error.none {return result,error;}result.dictionary_selections=copied;}

{let copied,error=cloneValue(self,value.dictionary_uses);if error!=Error.none {return result,error;}result.dictionary_uses=copied;}

{let copied,error=cloneValue(self,value.primitives);if error!=Error.none {return result,error;}result.primitives=copied;}

{let copied,error=cloneValue(self,value.loops);if error!=Error.none {return result,error;}result.loops=copied;}

{let copied,error=cloneValue(self,value.loop_carries);if error!=Error.none {return result,error;}result.loop_carries=copied;}

{let copied,error=cloneValue(self,value.resolver_ops);if error!=Error.none {return result,error;}result.resolver_ops=copied;}

{let copied,error=cloneValue(self,value.operation_values);if error!=Error.none {return result,error;}result.operation_values=copied;}

{let copied,error=cloneValue(self,value.handle_effects);if error!=Error.none {return result,error;}result.handle_effects=copied;}

{let copied,error=cloneValue(self,value.dispatch_signatures);if error!=Error.none {return result,error;}result.dispatch_signatures=copied;}

{let copied,error=cloneValue(self,value.diagnostics);if error!=Error.none {return result,error;}result.diagnostics=copied;}

{let copied,error=cloneValue(self,value.body_lowerings);if error!=Error.none {return result,error;}result.body_lowerings=copied;}

result.owner_id=blot_native::fresh_owner_id();

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_headers::Named)->blot_check_numeric_proof_headers::Named,Error {

var result=default<blot_check_numeric_proof_headers::Named>();

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.header);if error!=Error.none {return result,error;}result.header=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_headers::Owned)->blot_check_numeric_proof_headers::Owned,Error {

var result=default<blot_check_numeric_proof_headers::Owned>();

{let copied,error=cloneValue(self,value.arity);if error!=Error.none {return result,error;}result.arity=copied;}

{let copied,error=cloneValue(self,value.value_slots);if error!=Error.none {return result,error;}result.value_slots=copied;}

{let copied,error=cloneValue(self,value.proof_slots);if error!=Error.none {return result,error;}result.proof_slots=copied;}

{let copied,error=cloneValue(self,value.values);if error!=Error.none {return result,error;}result.values=copied;}

{let copied,error=cloneValue(self,value.operands);if error!=Error.none {return result,error;}result.operands=copied;}

{let copied,error=cloneValue(self,value.requirements);if error!=Error.none {return result,error;}result.requirements=copied;}

{let copied,error=cloneValue(self,value.result);if error!=Error.none {return result,error;}result.result=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_terms::Kind)->blot_check_numeric_proof_terms::Kind,Error {

match value {

blot_check_numeric_proof_terms::Kind.unsigned32=>{
return blot_check_numeric_proof_terms::Kind.unsigned32,Error.none;},

blot_check_numeric_proof_terms::Kind.array=>{
return blot_check_numeric_proof_terms::Kind.array,Error.none;},

blot_check_numeric_proof_terms::Kind.list=>{
return blot_check_numeric_proof_terms::Kind.list,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_terms::Term)->blot_check_numeric_proof_terms::Term,Error {

var result=default<blot_check_numeric_proof_terms::Term>();

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.a);if error!=Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self,value.b);if error!=Error.none {return result,error;}result.b=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_terms::Tag)->blot_check_numeric_proof_terms::Tag,Error {

match value {

blot_check_numeric_proof_terms::Tag.literal=>{
return blot_check_numeric_proof_terms::Tag.literal,Error.none;},

blot_check_numeric_proof_terms::Tag.formal=>{
return blot_check_numeric_proof_terms::Tag.formal,Error.none;},

blot_check_numeric_proof_terms::Tag.capture=>{
return blot_check_numeric_proof_terms::Tag.capture,Error.none;},

blot_check_numeric_proof_terms::Tag.version=>{
return blot_check_numeric_proof_terms::Tag.version,Error.none;},

blot_check_numeric_proof_terms::Tag.length=>{
return blot_check_numeric_proof_terms::Tag.length,Error.none;},

blot_check_numeric_proof_terms::Tag.complement=>{
return blot_check_numeric_proof_terms::Tag.complement,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_contracts::Requirement)->blot_check_numeric_proof_contracts::Requirement,Error {

var result=default<blot_check_numeric_proof_contracts::Requirement>();

{let copied,error=cloneValue(self,value.before);if error!=Error.none {return result,error;}result.before=copied;}

{let copied,error=cloneValue(self,value.proposition);if error!=Error.none {return result,error;}result.proposition=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {

var result=default<blot_check_numeric_proof_terms::Proposition>();

{let copied,error=cloneValue(self,value.relation);if error!=Error.none {return result,error;}result.relation=copied;}

{let copied,error=cloneValue(self,value.left);if error!=Error.none {return result,error;}result.left=copied;}

{let copied,error=cloneValue(self,value.right);if error!=Error.none {return result,error;}result.right=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_numeric_proof_terms::Relation)->blot_check_numeric_proof_terms::Relation,Error {

match value {

blot_check_numeric_proof_terms::Relation.eq=>{
return blot_check_numeric_proof_terms::Relation.eq,Error.none;},

blot_check_numeric_proof_terms::Relation.lt=>{
return blot_check_numeric_proof_terms::Relation.lt,Error.none;},

blot_check_numeric_proof_terms::Relation.le=>{
return blot_check_numeric_proof_terms::Relation.le,Error.none;},

blot_check_numeric_proof_terms::Relation.add_fits=>{
return blot_check_numeric_proof_terms::Relation.add_fits,Error.none;},

blot_check_numeric_proof_terms::Relation.sub_fits=>{
return blot_check_numeric_proof_terms::Relation.sub_fits,Error.none;},

blot_check_numeric_proof_terms::Relation.index=>{
return blot_check_numeric_proof_terms::Relation.index,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_capability_contracts::Collection)->blot_check_capability_contracts::Collection,Error {

var result=default<blot_check_capability_contracts::Collection>();

{let copied,error=cloneValue(self,value.nodes);if error!=Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self,value.words);if error!=Error.none {return result,error;}result.words=copied;}

{let copied,error=cloneValue(self,value.bindings);if error!=Error.none {return result,error;}result.bindings=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_capability_contracts::Term)->blot_check_capability_contracts::Term,Error {

var result=default<blot_check_capability_contracts::Term>();

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.a);if error!=Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self,value.b);if error!=Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self,value.c);if error!=Error.none {return result,error;}result.c=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_capability_contracts::Tag)->blot_check_capability_contracts::Tag,Error {

match value {

blot_check_capability_contracts::Tag.empty=>{
return blot_check_capability_contracts::Tag.empty,Error.none;},

blot_check_capability_contracts::Tag.unknown=>{
return blot_check_capability_contracts::Tag.unknown,Error.none;},

blot_check_capability_contracts::Tag.parameter=>{
return blot_check_capability_contracts::Tag.parameter,Error.none;},

blot_check_capability_contracts::Tag.authority=>{
return blot_check_capability_contracts::Tag.authority,Error.none;},

blot_check_capability_contracts::Tag.captures=>{
return blot_check_capability_contracts::Tag.captures,Error.none;},

blot_check_capability_contracts::Tag.product=>{
return blot_check_capability_contracts::Tag.product,Error.none;},

blot_check_capability_contracts::Tag.record=>{
return blot_check_capability_contracts::Tag.record,Error.none;},

blot_check_capability_contracts::Tag.wrapped=>{
return blot_check_capability_contracts::Tag.wrapped,Error.none;},

blot_check_capability_contracts::Tag.join=>{
return blot_check_capability_contracts::Tag.join,Error.none;},

blot_check_capability_contracts::Tag.project=>{
return blot_check_capability_contracts::Tag.project,Error.none;},

blot_check_capability_contracts::Tag.elements=>{
return blot_check_capability_contracts::Tag.elements,Error.none;},

blot_check_capability_contracts::Tag.argument=>{
return blot_check_capability_contracts::Tag.argument,Error.none;},

blot_check_capability_contracts::Tag.callable=>{
return blot_check_capability_contracts::Tag.callable,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_capability_contracts::Binding)->blot_check_capability_contracts::Binding,Error {

var result=default<blot_check_capability_contracts::Binding>();

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.root);if error!=Error.none {return result,error;}result.root=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::FieldName)->blot_check_core::FieldName,Error {

var result=default<blot_check_core::FieldName>();

{let copied,error=cloneValue(self,value.symbol);if error!=Error.none {return result,error;}result.symbol=copied;}

{let copied,error=cloneValue(self,value.spelling);if error!=Error.none {return result,error;}result.spelling=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Name)->blot_check_core::Name,Error {

var result=default<blot_check_core::Name>();

{let copied,error=cloneValue(self,value.start);if error!=Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self,value.len);if error!=Error.none {return result,error;}result.len=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::RuntimeName)->blot_check_core::RuntimeName,Error {

var result=default<blot_check_core::RuntimeName>();

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.point);if error!=Error.none {return result,error;}result.point=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::DeclarationDependencies)->blot_check_core::DeclarationDependencies,Error {

var result=default<blot_check_core::DeclarationDependencies>();

{let copied,error=cloneValue(self,value.references);if error!=Error.none {return result,error;}result.references=copied;}

{let copied,error=cloneValue(self,value.members);if error!=Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self,value.runtime_metadata);if error!=Error.none {return result,error;}result.runtime_metadata=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::List)->blot_check_core::List,Error {

var result=default<blot_check_core::List>();

{let copied,error=cloneValue(self,value.start);if error!=Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self,value.len);if error!=Error.none {return result,error;}result.len=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::BindingRef)->blot_check_core::BindingRef,Error {

var result=default<blot_check_core::BindingRef>();

{let copied,error=cloneValue(self,value.unit);if error!=Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::DependencyMember)->blot_check_core::DependencyMember,Error {

var result=default<blot_check_core::DependencyMember>();

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.operator);if error!=Error.none {return result,error;}result.operator=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::Operator)->blot_check_types::Operator,Error {

match value {

blot_check_types::Operator.none=>{
return blot_check_types::Operator.none,Error.none;},

blot_check_types::Operator.add=>{
return blot_check_types::Operator.add,Error.none;},

blot_check_types::Operator.sub=>{
return blot_check_types::Operator.sub,Error.none;},

blot_check_types::Operator.mul=>{
return blot_check_types::Operator.mul,Error.none;},

blot_check_types::Operator.div=>{
return blot_check_types::Operator.div,Error.none;},

blot_check_types::Operator.rem=>{
return blot_check_types::Operator.rem,Error.none;},

blot_check_types::Operator.equal=>{
return blot_check_types::Operator.equal,Error.none;},

blot_check_types::Operator.not_equal=>{
return blot_check_types::Operator.not_equal,Error.none;},

blot_check_types::Operator.less=>{
return blot_check_types::Operator.less,Error.none;},

blot_check_types::Operator.less_equal=>{
return blot_check_types::Operator.less_equal,Error.none;},

blot_check_types::Operator.greater=>{
return blot_check_types::Operator.greater,Error.none;},

blot_check_types::Operator.greater_equal=>{
return blot_check_types::Operator.greater_equal,Error.none;},

blot_check_types::Operator.bit_and=>{
return blot_check_types::Operator.bit_and,Error.none;},

blot_check_types::Operator.bit_or=>{
return blot_check_types::Operator.bit_or,Error.none;},

blot_check_types::Operator.bit_xor=>{
return blot_check_types::Operator.bit_xor,Error.none;},

blot_check_types::Operator.shift_left=>{
return blot_check_types::Operator.shift_left,Error.none;},

blot_check_types::Operator.shift_right=>{
return blot_check_types::Operator.shift_right,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::ErasedDeclarationReference)->blot_check_core::ErasedDeclarationReference,Error {

var result=default<blot_check_core::ErasedDeclarationReference>();

{let copied,error=cloneValue(self,value.node);if error!=Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::RequestLoopInfo)->blot_check_core::RequestLoopInfo,Error {

var result=default<blot_check_core::RequestLoopInfo>();

{let copied,error=cloneValue(self,value.computation);if error!=Error.none {return result,error;}result.computation=copied;}

{let copied,error=cloneValue(self,value.action_type);if error!=Error.none {return result,error;}result.action_type=copied;}

{let copied,error=cloneValue(self,value.value_type);if error!=Error.none {return result,error;}result.value_type=copied;}

{let copied,error=cloneValue(self,value.result_type);if error!=Error.none {return result,error;}result.result_type=copied;}

{let copied,error=cloneValue(self,value.state_type);if error!=Error.none {return result,error;}result.state_type=copied;}

{let copied,error=cloneValue(self,value.arms);if error!=Error.none {return result,error;}result.arms=copied;}

{let copied,error=cloneValue(self,value.completion_pattern);if error!=Error.none {return result,error;}result.completion_pattern=copied;}

{let copied,error=cloneValue(self,value.completion_body);if error!=Error.none {return result,error;}result.completion_body=copied;}

{let copied,error=cloneValue(self,value.completion_state_bindings);if error!=Error.none {return result,error;}result.completion_state_bindings=copied;}

{let copied,error=cloneValue(self,value.carries);if error!=Error.none {return result,error;}result.carries=copied;}

{let copied,error=cloneValue(self,value.return_target);if error!=Error.none {return result,error;}result.return_target=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::RequestArm)->blot_check_core::RequestArm,Error {

var result=default<blot_check_core::RequestArm>();

{let copied,error=cloneValue(self,value.operation);if error!=Error.none {return result,error;}result.operation=copied;}

{let copied,error=cloneValue(self,value.callback);if error!=Error.none {return result,error;}result.callback=copied;}

{let copied,error=cloneValue(self,value.selector);if error!=Error.none {return result,error;}result.selector=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Types)->blot_check_core::Types,Error {

var result=default<blot_check_core::Types>();

{let copied,error=cloneValue(self,value.nodes);if error!=Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self,value.extra);if error!=Error.none {return result,error;}result.extra=copied;}

{let copied,error=cloneValue(self,value.effects);if error!=Error.none {return result,error;}result.effects=copied;}

{let copied,error=cloneValue(self,value.operations);if error!=Error.none {return result,error;}result.operations=copied;}

{let copied,error=cloneValue(self,value.quantifier_goals);if error!=Error.none {return result,error;}result.quantifier_goals=copied;}

{let copied,error=cloneValue(self,value.quantifier_obligations);if error!=Error.none {return result,error;}result.quantifier_obligations=copied;}

result.owner_id=blot_native::fresh_owner_id();

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::Node)->blot_check_types::Node,Error {

var result=default<blot_check_types::Node>();

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.closed_height);if error!=Error.none {return result,error;}result.closed_height=copied;}

{let copied,error=cloneValue(self,value.closed_generation);if error!=Error.none {return result,error;}result.closed_generation=copied;}

{let copied,error=cloneValue(self,value.a);if error!=Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self,value.b);if error!=Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self,value.c);if error!=Error.none {return result,error;}result.c=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::Tag)->blot_check_types::Tag,Error {

match value {

blot_check_types::Tag.absent=>{
return blot_check_types::Tag.absent,Error.none;},

blot_check_types::Tag.unit=>{
return blot_check_types::Tag.unit,Error.none;},

blot_check_types::Tag.boolean=>{
return blot_check_types::Tag.boolean,Error.none;},

blot_check_types::Tag.unsigned32=>{
return blot_check_types::Tag.unsigned32,Error.none;},

blot_check_types::Tag.floating32=>{
return blot_check_types::Tag.floating32,Error.none;},

blot_check_types::Tag.never=>{
return blot_check_types::Tag.never,Error.none;},

blot_check_types::Tag.variable=>{
return blot_check_types::Tag.variable,Error.none;},

blot_check_types::Tag.function=>{
return blot_check_types::Tag.function,Error.none;},

blot_check_types::Tag.product=>{
return blot_check_types::Tag.product,Error.none;},

blot_check_types::Tag.record=>{
return blot_check_types::Tag.record,Error.none;},

blot_check_types::Tag.nominal=>{
return blot_check_types::Tag.nominal,Error.none;},

blot_check_types::Tag.array=>{
return blot_check_types::Tag.array,Error.none;},

blot_check_types::Tag.list=>{
return blot_check_types::Tag.list,Error.none;},

blot_check_types::Tag.cursor=>{
return blot_check_types::Tag.cursor,Error.none;},

blot_check_types::Tag.type_constructor=>{
return blot_check_types::Tag.type_constructor,Error.none;},

blot_check_types::Tag.resolver=>{
return blot_check_types::Tag.resolver,Error.none;},

blot_check_types::Tag.provider=>{
return blot_check_types::Tag.provider,Error.none;},

blot_check_types::Tag.state_provider=>{
return blot_check_types::Tag.state_provider,Error.none;},

blot_check_types::Tag.projection=>{
return blot_check_types::Tag.projection,Error.none;},

blot_check_types::Tag.scoped=>{
return blot_check_types::Tag.scoped,Error.none;},

blot_check_types::Tag.instance_selection=>{
return blot_check_types::Tag.instance_selection,Error.none;},

blot_check_types::Tag.erased_proof=>{
return blot_check_types::Tag.erased_proof,Error.none;},

blot_check_types::Tag.forall=>{
return blot_check_types::Tag.forall,Error.none;},

blot_check_types::Tag.existential=>{
return blot_check_types::Tag.existential,Error.none;},

blot_check_types::Tag.bound=>{
return blot_check_types::Tag.bound,Error.none;},

blot_check_types::Tag.rigid=>{
return blot_check_types::Tag.rigid,Error.none;},

blot_check_types::Tag.usage=>{
return blot_check_types::Tag.usage,Error.none;},

blot_check_types::Tag.instance_version=>{
return blot_check_types::Tag.instance_version,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::EffectRows)->blot_check_core::EffectRows,Error {

var result=default<blot_check_core::EffectRows>();

{let copied,error=cloneValue(self,value.rows);if error!=Error.none {return result,error;}result.rows=copied;}

{let copied,error=cloneValue(self,value.labels);if error!=Error.none {return result,error;}result.labels=copied;}

{let copied,error=cloneValue(self,value.variable_count);if error!=Error.none {return result,error;}result.variable_count=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_effects::Row)->blot_check_effects::Row,Error {

var result=default<blot_check_effects::Row>();

{let copied,error=cloneValue(self,value.labels);if error!=Error.none {return result,error;}result.labels=copied;}

{let copied,error=cloneValue(self,value.tail);if error!=Error.none {return result,error;}result.tail=copied;}

{let copied,error=cloneValue(self,value.cursor);if error!=Error.none {return result,error;}result.cursor=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_effects::List)->blot_check_effects::List,Error {

var result=default<blot_check_effects::List>();

{let copied,error=cloneValue(self,value.start);if error!=Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self,value.len);if error!=Error.none {return result,error;}result.len=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_effects::Tail)->blot_check_effects::Tail,Error {

match value {

blot_check_effects::Tail.closed=>{
return blot_check_effects::Tail.closed,Error.none;},

blot_check_effects::Tail.variable payload=>{
let value,error_value=cloneValue(self,payload.value);if error_value!=Error.none {return default<blot_check_effects::Tail>(),error_value;}
return blot_check_effects::Tail.variable {value:value},Error.none;},

blot_check_effects::Tail.parameter payload=>{
let value,error_value=cloneValue(self,payload.value);if error_value!=Error.none {return default<blot_check_effects::Tail>(),error_value;}
return blot_check_effects::Tail.parameter {value:value},Error.none;},

blot_check_effects::Tail.formal payload=>{
let value,error_value=cloneValue(self,payload.value);if error_value!=Error.none {return default<blot_check_effects::Tail>(),error_value;}
return blot_check_effects::Tail.formal {value:value},Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_types::Operation)->blot_check_types::Operation,Error {

var result=default<blot_check_types::Operation>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.arguments);if error!=Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self,value.instance);if error!=Error.none {return result,error;}result.instance=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::NominalIdentity)->blot_check_types::NominalIdentity,Error {

var result=default<blot_check_types::NominalIdentity>();

{let copied,error=cloneValue(self,value.unit);if error!=Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self,value.decl);if error!=Error.none {return result,error;}result.decl=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::List)->blot_check_types::List,Error {

var result=default<blot_check_types::List>();

{let copied,error=cloneValue(self,value.start);if error!=Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self,value.len);if error!=Error.none {return result,error;}result.len=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::QuantifierGoals)->blot_check_types::QuantifierGoals,Error {

var result=default<blot_check_types::QuantifierGoals>();

{let copied,error=cloneValue(self,value.owner);if error!=Error.none {return result,error;}result.owner=copied;}

{let copied,error=cloneValue(self,value.goals);if error!=Error.none {return result,error;}result.goals=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::Obligation)->blot_check_types::Obligation,Error {

var result=default<blot_check_types::Obligation>();

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.source);if error!=Error.none {return result,error;}result.source=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.result);if error!=Error.none {return result,error;}result.result=copied;}

{let copied,error=cloneValue(self,value.other);if error!=Error.none {return result,error;}result.other=copied;}

{let copied,error=cloneValue(self,value.signature);if error!=Error.none {return result,error;}result.signature=copied;}

{let copied,error=cloneValue(self,value.operator);if error!=Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.explicit);if error!=Error.none {return result,error;}result.explicit=copied;}

{let copied,error=cloneValue(self,value.qualification_span);if error!=Error.none {return result,error;}result.qualification_span=copied;}

{let copied,error=cloneValue(self,value.qualification_unit);if error!=Error.none {return result,error;}result.qualification_unit=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_types::ObligationKind)->blot_check_types::ObligationKind,Error {

match value {

blot_check_types::ObligationKind.arithmetic=>{
return blot_check_types::ObligationKind.arithmetic,Error.none;},

blot_check_types::ObligationKind.ordered=>{
return blot_check_types::ObligationKind.ordered,Error.none;},

blot_check_types::ObligationKind.equality=>{
return blot_check_types::ObligationKind.equality,Error.none;},

blot_check_types::ObligationKind.integer=>{
return blot_check_types::ObligationKind.integer,Error.none;},

blot_check_types::ObligationKind.field=>{
return blot_check_types::ObligationKind.field,Error.none;},

blot_check_types::ObligationKind.writable_field=>{
return blot_check_types::ObligationKind.writable_field,Error.none;},

blot_check_types::ObligationKind.dispatch=>{
return blot_check_types::ObligationKind.dispatch,Error.none;},

blot_check_types::ObligationKind.result_dispatch=>{
return blot_check_types::ObligationKind.result_dispatch,Error.none;},

blot_check_types::ObligationKind.monad_factory=>{
return blot_check_types::ObligationKind.monad_factory,Error.none;},

blot_check_types::ObligationKind.resolver_dispatch=>{
return blot_check_types::ObligationKind.resolver_dispatch,Error.none;},

blot_check_types::ObligationKind.resolver_shape=>{
return blot_check_types::ObligationKind.resolver_shape,Error.none;},

blot_check_types::ObligationKind.effect_operation=>{
return blot_check_types::ObligationKind.effect_operation,Error.none;},

blot_check_types::ObligationKind.effect_handler=>{
return blot_check_types::ObligationKind.effect_handler,Error.none;},

blot_check_types::ObligationKind.receiver=>{
return blot_check_types::ObligationKind.receiver,Error.none;},

blot_check_types::ObligationKind.update=>{
return blot_check_types::ObligationKind.update,Error.none;},

blot_check_types::ObligationKind.type_rep=>{
return blot_check_types::ObligationKind.type_rep,Error.none;},

blot_check_types::ObligationKind.effect_rep=>{
return blot_check_types::ObligationKind.effect_rep,Error.none;},

blot_check_types::ObligationKind.type_head=>{
return blot_check_types::ObligationKind.type_head,Error.none;},

blot_check_types::ObligationKind.collection=>{
return blot_check_types::ObligationKind.collection,Error.none;},

blot_check_types::ObligationKind.record_merge=>{
return blot_check_types::ObligationKind.record_merge,Error.none;},

blot_check_types::ObligationKind.callee_use=>{
return blot_check_types::ObligationKind.callee_use,Error.none;},

blot_check_types::ObligationKind.type_eq=>{
return blot_check_types::ObligationKind.type_eq,Error.none;},

blot_check_types::ObligationKind.contract=>{
return blot_check_types::ObligationKind.contract,Error.none;},

blot_check_types::ObligationKind.task_receive=>{
return blot_check_types::ObligationKind.task_receive,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_parse_ast::Span)->blot_parse_ast::Span,Error {

var result=default<blot_parse_ast::Span>();

{let copied,error=cloneValue(self,value.start);if error!=Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self,value.end);if error!=Error.none {return result,error;}result.end=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Node)->blot_check_core::Node,Error {

var result=default<blot_check_core::Node>();

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.op);if error!=Error.none {return result,error;}result.op=copied;}

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.a);if error!=Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self,value.b);if error!=Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self,value.c);if error!=Error.none {return result,error;}result.c=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Tag)->blot_check_core::Tag,Error {

match value {

blot_check_core::Tag.invalid=>{
return blot_check_core::Tag.invalid,Error.none;},

blot_check_core::Tag.constant=>{
return blot_check_core::Tag.constant,Error.none;},

blot_check_core::Tag.reference=>{
return blot_check_core::Tag.reference,Error.none;},

blot_check_core::Tag.scalar=>{
return blot_check_core::Tag.scalar,Error.none;},

blot_check_core::Tag.logical=>{
return blot_check_core::Tag.logical,Error.none;},

blot_check_core::Tag.call=>{
return blot_check_core::Tag.call,Error.none;},

blot_check_core::Tag.if_value=>{
return blot_check_core::Tag.if_value,Error.none;},

blot_check_core::Tag.block_=>{
return blot_check_core::Tag.block_,Error.none;},

blot_check_core::Tag.suite=>{
return blot_check_core::Tag.suite,Error.none;},

blot_check_core::Tag.bind=>{
return blot_check_core::Tag.bind,Error.none;},

blot_check_core::Tag.return_=>{
return blot_check_core::Tag.return_,Error.none;},

blot_check_core::Tag.if_stmt=>{
return blot_check_core::Tag.if_stmt,Error.none;},

blot_check_core::Tag.product=>{
return blot_check_core::Tag.product,Error.none;},

blot_check_core::Tag.record=>{
return blot_check_core::Tag.record,Error.none;},

blot_check_core::Tag.construct=>{
return blot_check_core::Tag.construct,Error.none;},

blot_check_core::Tag.project=>{
return blot_check_core::Tag.project,Error.none;},

blot_check_core::Tag.match_=>{
return blot_check_core::Tag.match_,Error.none;},

blot_check_core::Tag.pattern_bind=>{
return blot_check_core::Tag.pattern_bind,Error.none;},

blot_check_core::Tag.update=>{
return blot_check_core::Tag.update,Error.none;},

blot_check_core::Tag.array=>{
return blot_check_core::Tag.array,Error.none;},

blot_check_core::Tag.array_op=>{
return blot_check_core::Tag.array_op,Error.none;},

blot_check_core::Tag.closure=>{
return blot_check_core::Tag.closure,Error.none;},

blot_check_core::Tag.apply=>{
return blot_check_core::Tag.apply,Error.none;},

blot_check_core::Tag.constructor_function=>{
return blot_check_core::Tag.constructor_function,Error.none;},

blot_check_core::Tag.associated=>{
return blot_check_core::Tag.associated,Error.none;},

blot_check_core::Tag.primitive_function=>{
return blot_check_core::Tag.primitive_function,Error.none;},

blot_check_core::Tag.panic=>{
return blot_check_core::Tag.panic,Error.none;},

blot_check_core::Tag.loop_=>{
return blot_check_core::Tag.loop_,Error.none;},

blot_check_core::Tag.break_=>{
return blot_check_core::Tag.break_,Error.none;},

blot_check_core::Tag.type_same=>{
return blot_check_core::Tag.type_same,Error.none;},

blot_check_core::Tag.result_associated=>{
return blot_check_core::Tag.result_associated,Error.none;},

blot_check_core::Tag.type_constructor=>{
return blot_check_core::Tag.type_constructor,Error.none;},

blot_check_core::Tag.resolver_op=>{
return blot_check_core::Tag.resolver_op,Error.none;},

blot_check_core::Tag.operation_value=>{
return blot_check_core::Tag.operation_value,Error.none;},

blot_check_core::Tag.effect_provider=>{
return blot_check_core::Tag.effect_provider,Error.none;},

blot_check_core::Tag.state_provider=>{
return blot_check_core::Tag.state_provider,Error.none;},

blot_check_core::Tag.handle=>{
return blot_check_core::Tag.handle,Error.none;},

blot_check_core::Tag.effect_reflection=>{
return blot_check_core::Tag.effect_reflection,Error.none;},

blot_check_core::Tag.computation=>{
return blot_check_core::Tag.computation,Error.none;},

blot_check_core::Tag.request_loop=>{
return blot_check_core::Tag.request_loop,Error.none;},

blot_check_core::Tag.request_decision=>{
return blot_check_core::Tag.request_decision,Error.none;},

blot_check_core::Tag.record_merge=>{
return blot_check_core::Tag.record_merge,Error.none;},

blot_check_core::Tag.contract_method=>{
return blot_check_core::Tag.contract_method,Error.none;},

blot_check_core::Tag.effect_scope=>{
return blot_check_core::Tag.effect_scope,Error.none;},

blot_check_core::Tag.proof_guard=>{
return blot_check_core::Tag.proof_guard,Error.none;},

blot_check_core::Tag.package_pack=>{
return blot_check_core::Tag.package_pack,Error.none;},

blot_check_core::Tag.package_unpack=>{
return blot_check_core::Tag.package_unpack,Error.none;},

blot_check_core::Tag.staging=>{
return blot_check_core::Tag.staging,Error.none;},

blot_check_core::Tag.usage_borrow=>{
return blot_check_core::Tag.usage_borrow,Error.none;},

blot_check_core::Tag.usage_read=>{
return blot_check_core::Tag.usage_read,Error.none;},

blot_check_core::Tag.resource_scope=>{
return blot_check_core::Tag.resource_scope,Error.none;},

blot_check_core::Tag.usage_share=>{
return blot_check_core::Tag.usage_share,Error.none;},

blot_check_core::Tag.resource_acquire=>{
return blot_check_core::Tag.resource_acquire,Error.none;},

blot_check_core::Tag.resource_release=>{
return blot_check_core::Tag.resource_release,Error.none;},

blot_check_core::Tag.task=>{
return blot_check_core::Tag.task,Error.none;},

blot_check_core::Tag.storage=>{
return blot_check_core::Tag.storage,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::Op)->blot_check_core::Op,Error {

match value {

blot_check_core::Op.none=>{
return blot_check_core::Op.none,Error.none;},

blot_check_core::Op.add=>{
return blot_check_core::Op.add,Error.none;},

blot_check_core::Op.sub=>{
return blot_check_core::Op.sub,Error.none;},

blot_check_core::Op.mul=>{
return blot_check_core::Op.mul,Error.none;},

blot_check_core::Op.div=>{
return blot_check_core::Op.div,Error.none;},

blot_check_core::Op.rem=>{
return blot_check_core::Op.rem,Error.none;},

blot_check_core::Op.equal=>{
return blot_check_core::Op.equal,Error.none;},

blot_check_core::Op.not_equal=>{
return blot_check_core::Op.not_equal,Error.none;},

blot_check_core::Op.less=>{
return blot_check_core::Op.less,Error.none;},

blot_check_core::Op.less_equal=>{
return blot_check_core::Op.less_equal,Error.none;},

blot_check_core::Op.greater=>{
return blot_check_core::Op.greater,Error.none;},

blot_check_core::Op.greater_equal=>{
return blot_check_core::Op.greater_equal,Error.none;},

blot_check_core::Op.bit_and=>{
return blot_check_core::Op.bit_and,Error.none;},

blot_check_core::Op.bit_or=>{
return blot_check_core::Op.bit_or,Error.none;},

blot_check_core::Op.bit_xor=>{
return blot_check_core::Op.bit_xor,Error.none;},

blot_check_core::Op.shift_left=>{
return blot_check_core::Op.shift_left,Error.none;},

blot_check_core::Op.shift_right=>{
return blot_check_core::Op.shift_right,Error.none;},

blot_check_core::Op.and_=>{
return blot_check_core::Op.and_,Error.none;},

blot_check_core::Op.or_=>{
return blot_check_core::Op.or_,Error.none;},

blot_check_core::Op.neg=>{
return blot_check_core::Op.neg,Error.none;},

blot_check_core::Op.abs=>{
return blot_check_core::Op.abs,Error.none;},

blot_check_core::Op.ceil=>{
return blot_check_core::Op.ceil,Error.none;},

blot_check_core::Op.floor=>{
return blot_check_core::Op.floor,Error.none;},

blot_check_core::Op.trunc=>{
return blot_check_core::Op.trunc,Error.none;},

blot_check_core::Op.sqrt=>{
return blot_check_core::Op.sqrt,Error.none;},

blot_check_core::Op.convert_u32_f32=>{
return blot_check_core::Op.convert_u32_f32,Error.none;},

blot_check_core::Op.convert_f32_u32=>{
return blot_check_core::Op.convert_f32_u32,Error.none;},

blot_check_core::Op.shift_right_signed=>{
return blot_check_core::Op.shift_right_signed,Error.none;},

blot_check_core::Op.min=>{
return blot_check_core::Op.min,Error.none;},

blot_check_core::Op.max=>{
return blot_check_core::Op.max,Error.none;},

blot_check_core::Op.bit_not=>{
return blot_check_core::Op.bit_not,Error.none;},

blot_check_core::Op.bit_andnot=>{
return blot_check_core::Op.bit_andnot,Error.none;},

blot_check_core::Op.any_true=>{
return blot_check_core::Op.any_true,Error.none;},

blot_check_core::Op.all_true=>{
return blot_check_core::Op.all_true,Error.none;},

blot_check_core::Op.select=>{
return blot_check_core::Op.select,Error.none;},

blot_check_core::Op.shuffle=>{
return blot_check_core::Op.shuffle,Error.none;},

blot_check_core::Op.swizzle=>{
return blot_check_core::Op.swizzle,Error.none;},

blot_check_core::Op.broadcast=>{
return blot_check_core::Op.broadcast,Error.none;},

blot_check_core::Op.bits=>{
return blot_check_core::Op.bits,Error.none;},

blot_check_core::Op.from_bits=>{
return blot_check_core::Op.from_bits,Error.none;},

blot_check_core::Op.relaxed_madd=>{
return blot_check_core::Op.relaxed_madd,Error.none;},

blot_check_core::Op.relaxed_nmadd=>{
return blot_check_core::Op.relaxed_nmadd,Error.none;},

blot_check_core::Op.convert_i32_f32=>{
return blot_check_core::Op.convert_i32_f32,Error.none;},

blot_check_core::Op.convert_f32_i32=>{
return blot_check_core::Op.convert_f32_i32,Error.none;},

blot_check_core::Op.continue_=>{
return blot_check_core::Op.continue_,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::Binding)->blot_check_core::Binding,Error {

var result=default<blot_check_core::Binding>();

{let copied,error=cloneValue(self,value.capability_flow);if error!=Error.none {return result,error;}result.capability_flow=copied;}

{let copied,error=cloneValue(self,value.capability_parameters);if error!=Error.none {return result,error;}result.capability_parameters=copied;}

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.initializer);if error!=Error.none {return result,error;}result.initializer=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.scheme);if error!=Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self,value.public_variables);if error!=Error.none {return result,error;}result.public_variables=copied;}

{let copied,error=cloneValue(self,value.public_rows);if error!=Error.none {return result,error;}result.public_rows=copied;}

{let copied,error=cloneValue(self,value.has_explicit);if error!=Error.none {return result,error;}result.has_explicit=copied;}

{let copied,error=cloneValue(self,value.body_id);if error!=Error.none {return result,error;}result.body_id=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_capability_flow::Contract)->blot_check_capability_flow::Contract,Error {

match value {

blot_check_capability_flow::Contract.unknown=>{
return blot_check_capability_flow::Contract.unknown,Error.none;},

blot_check_capability_flow::Contract.identity=>{
return blot_check_capability_flow::Contract.identity,Error.none;},

blot_check_capability_flow::Contract.invoke_unit=>{
return blot_check_capability_flow::Contract.invoke_unit,Error.none;},

blot_check_capability_flow::Contract.member_unit=>{
return blot_check_capability_flow::Contract.member_unit,Error.none;},

blot_check_capability_flow::Contract.invoke_with_capability=>{
return blot_check_capability_flow::Contract.invoke_with_capability,Error.none;},

blot_check_capability_flow::Contract.member_first_unit=>{
return blot_check_capability_flow::Contract.member_first_unit,Error.none;},

blot_check_capability_flow::Contract.member_second_unit=>{
return blot_check_capability_flow::Contract.member_second_unit,Error.none;},

blot_check_capability_flow::Contract.input_shape=>{
return blot_check_capability_flow::Contract.input_shape,Error.none;},

blot_check_capability_flow::Contract.consume_task=>{
return blot_check_capability_flow::Contract.consume_task,Error.none;},

blot_check_capability_flow::Contract.scope_task=>{
return blot_check_capability_flow::Contract.scope_task,Error.none;},

blot_check_capability_flow::Contract.spawn_task=>{
return blot_check_capability_flow::Contract.spawn_task,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_capability_flow::Parameters)->blot_check_capability_flow::Parameters,Error {

var result=default<blot_check_capability_flow::Parameters>();

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.mask);if error!=Error.none {return result,error;}result.mask=copied;}

{let copied,error=cloneValue(self,value.inputs);if error!=Error.none {return result,error;}result.inputs=copied;}

{let copied,error=cloneValue(self,value.invocation_arguments);if error!=Error.none {return result,error;}result.invocation_arguments=copied;}

{let copied,error=cloneValue(self,value.invocation_count);if error!=Error.none {return result,error;}result.invocation_count=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_capability_flow::ParameterResult)->blot_check_capability_flow::ParameterResult,Error {

match value {

blot_check_capability_flow::ParameterResult.product=>{
return blot_check_capability_flow::ParameterResult.product,Error.none;},

blot_check_capability_flow::ParameterResult.invoke_unit=>{
return blot_check_capability_flow::ParameterResult.invoke_unit,Error.none;},

blot_check_capability_flow::ParameterResult.invalid=>{
return blot_check_capability_flow::ParameterResult.invalid,Error.none;},

blot_check_capability_flow::ParameterResult.member_closure_unit=>{
return blot_check_capability_flow::ParameterResult.member_closure_unit,Error.none;},

blot_check_capability_flow::ParameterResult.captured_unit=>{
return blot_check_capability_flow::ParameterResult.captured_unit,Error.none;},

blot_check_capability_flow::ParameterResult.invoke_input=>{
return blot_check_capability_flow::ParameterResult.invoke_input,Error.none;},

blot_check_capability_flow::ParameterResult.invoke_inputs=>{
return blot_check_capability_flow::ParameterResult.invoke_inputs,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Kind)->blot_reuse_principal_interface::Kind,Error {

match value {

blot_reuse_principal_interface::Kind.global=>{
return blot_reuse_principal_interface::Kind.global,Error.none;},

blot_reuse_principal_interface::Kind.local=>{
return blot_reuse_principal_interface::Kind.local,Error.none;},

blot_reuse_principal_interface::Kind.parameter=>{
return blot_reuse_principal_interface::Kind.parameter,Error.none;},

blot_reuse_principal_interface::Kind.external=>{
return blot_reuse_principal_interface::Kind.external,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_types::Scheme)->blot_check_types::Scheme,Error {

var result=default<blot_check_types::Scheme>();

{let copied,error=cloneValue(self,value.root);if error!=Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.row_variables);if error!=Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self,value.closed_rows);if error!=Error.none {return result,error;}result.closed_rows=copied;}

{let copied,error=cloneValue(self,value.obligations);if error!=Error.none {return result,error;}result.obligations=copied;}

{let copied,error=cloneValue(self,value.generative);if error!=Error.none {return result,error;}result.generative=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Body)->blot_check_core::Body,Error {

var result=default<blot_check_core::Body>();

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.root);if error!=Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.scheme);if error!=Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self,value.closed_rows);if error!=Error.none {return result,error;}result.closed_rows=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

{let copied,error=cloneValue(self,value.declaration_name);if error!=Error.none {return result,error;}result.declaration_name=copied;}

{let copied,error=cloneValue(self,value.export_name);if error!=Error.none {return result,error;}result.export_name=copied;}

{let copied,error=cloneValue(self,value.exported);if error!=Error.none {return result,error;}result.exported=copied;}

{let copied,error=cloneValue(self,value.runtime);if error!=Error.none {return result,error;}result.runtime=copied;}

{let copied,error=cloneValue(self,value.is_function);if error!=Error.none {return result,error;}result.is_function=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Parameter)->blot_check_core::Parameter,Error {

var result=default<blot_check_core::Parameter>();

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

{let copied,error=cloneValue(self,value.inferred);if error!=Error.none {return result,error;}result.inferred=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::CallInfo)->blot_check_core::CallInfo,Error {

var result=default<blot_check_core::CallInfo>();

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self,value.callee_type);if error!=Error.none {return result,error;}result.callee_type=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Merge)->blot_check_core::Merge,Error {

var result=default<blot_check_core::Merge>();

{let copied,error=cloneValue(self,value.node);if error!=Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self,value.result);if error!=Error.none {return result,error;}result.result=copied;}

{let copied,error=cloneValue(self,value.then_binding);if error!=Error.none {return result,error;}result.then_binding=copied;}

{let copied,error=cloneValue(self,value.else_binding);if error!=Error.none {return result,error;}result.else_binding=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Obligation)->blot_check_core::Obligation,Error {

var result=default<blot_check_core::Obligation>();

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.result);if error!=Error.none {return result,error;}result.result=copied;}

{let copied,error=cloneValue(self,value.other);if error!=Error.none {return result,error;}result.other=copied;}

{let copied,error=cloneValue(self,value.signature);if error!=Error.none {return result,error;}result.signature=copied;}

{let copied,error=cloneValue(self,value.operator);if error!=Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.explicit);if error!=Error.none {return result,error;}result.explicit=copied;}

{let copied,error=cloneValue(self,value.qualification_span);if error!=Error.none {return result,error;}result.qualification_span=copied;}

{let copied,error=cloneValue(self,value.qualification_unit);if error!=Error.none {return result,error;}result.qualification_unit=copied;}

{let copied,error=cloneValue(self,value.diagnostic_name);if error!=Error.none {return result,error;}result.diagnostic_name=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Nominal)->blot_check_core::Nominal,Error {

var result=default<blot_check_core::Nominal>();

{let copied,error=cloneValue(self,value.affine);if error!=Error.none {return result,error;}result.affine=copied;}

{let copied,error=cloneValue(self,value.has_usage);if error!=Error.none {return result,error;}result.has_usage=copied;}

{let copied,error=cloneValue(self,value.closed_storage);if error!=Error.none {return result,error;}result.closed_storage=copied;}

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.is_opaque);if error!=Error.none {return result,error;}result.is_opaque=copied;}

{let copied,error=cloneValue(self,value.storage);if error!=Error.none {return result,error;}result.storage=copied;}

{let copied,error=cloneValue(self,value.diagnostic_name);if error!=Error.none {return result,error;}result.diagnostic_name=copied;}

{let copied,error=cloneValue(self,value.diagnostic_origin);if error!=Error.none {return result,error;}result.diagnostic_origin=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.constructors);if error!=Error.none {return result,error;}result.constructors=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_backend_opaque_storage::Storage)->blot_backend_opaque_storage::Storage,Error {

var result=default<blot_backend_opaque_storage::Storage>();

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.parameter);if error!=Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self,value.selector);if error!=Error.none {return result,error;}result.selector=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_backend_opaque_storage::Kind)->blot_backend_opaque_storage::Kind,Error {

match value {

blot_backend_opaque_storage::Kind.unknown=>{
return blot_backend_opaque_storage::Kind.unknown,Error.none;},

blot_backend_opaque_storage::Kind.unit=>{
return blot_backend_opaque_storage::Kind.unit,Error.none;},

blot_backend_opaque_storage::Kind.boolean=>{
return blot_backend_opaque_storage::Kind.boolean,Error.none;},

blot_backend_opaque_storage::Kind.unsigned32=>{
return blot_backend_opaque_storage::Kind.unsigned32,Error.none;},

blot_backend_opaque_storage::Kind.floating32=>{
return blot_backend_opaque_storage::Kind.floating32,Error.none;},

blot_backend_opaque_storage::Kind.reference=>{
return blot_backend_opaque_storage::Kind.reference,Error.none;},

blot_backend_opaque_storage::Kind.parameter=>{
return blot_backend_opaque_storage::Kind.parameter,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::OperationName)->blot_check_core::OperationName,Error {

var result=default<blot_check_core::OperationName>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.diagnostic_name);if error!=Error.none {return result,error;}result.diagnostic_name=copied;}

{let copied,error=cloneValue(self,value.diagnostic_origin);if error!=Error.none {return result,error;}result.diagnostic_origin=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.parameter);if error!=Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self,value.result);if error!=Error.none {return result,error;}result.result=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Constructor)->blot_check_core::Constructor,Error {

var result=default<blot_check_core::Constructor>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.nominal);if error!=Error.none {return result,error;}result.nominal=copied;}

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.scheme);if error!=Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self,value.payload);if error!=Error.none {return result,error;}result.payload=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Projection)->blot_check_core::Projection,Error {

var result=default<blot_check_core::Projection>();

{let copied,error=cloneValue(self,value.nominal);if error!=Error.none {return result,error;}result.nominal=copied;}

{let copied,error=cloneValue(self,value.field);if error!=Error.none {return result,error;}result.field=copied;}

{let copied,error=cloneValue(self,value.source_type);if error!=Error.none {return result,error;}result.source_type=copied;}

{let copied,error=cloneValue(self,value.result_type);if error!=Error.none {return result,error;}result.result_type=copied;}

{let copied,error=cloneValue(self,value.variants);if error!=Error.none {return result,error;}result.variants=copied;}

{let copied,error=cloneValue(self,value.diagnostic_point);if error!=Error.none {return result,error;}result.diagnostic_point=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::ProjectionVariant)->blot_check_core::ProjectionVariant,Error {

var result=default<blot_check_core::ProjectionVariant>();

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.field);if error!=Error.none {return result,error;}result.field=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Pattern)->blot_check_core::Pattern,Error {

var result=default<blot_check_core::Pattern>();

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.a);if error!=Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self,value.b);if error!=Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self,value.c);if error!=Error.none {return result,error;}result.c=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::PatternTag)->blot_check_core::PatternTag,Error {

match value {

blot_check_core::PatternTag.invalid=>{
return blot_check_core::PatternTag.invalid,Error.none;},

blot_check_core::PatternTag.wildcard=>{
return blot_check_core::PatternTag.wildcard,Error.none;},

blot_check_core::PatternTag.bind=>{
return blot_check_core::PatternTag.bind,Error.none;},

blot_check_core::PatternTag.constant=>{
return blot_check_core::PatternTag.constant,Error.none;},

blot_check_core::PatternTag.value=>{
return blot_check_core::PatternTag.value,Error.none;},

blot_check_core::PatternTag.product=>{
return blot_check_core::PatternTag.product,Error.none;},

blot_check_core::PatternTag.constructor=>{
return blot_check_core::PatternTag.constructor,Error.none;},

blot_check_core::PatternTag.record_payload=>{
return blot_check_core::PatternTag.record_payload,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::PatternRow)->blot_check_core::PatternRow,Error {

var result=default<blot_check_core::PatternRow>();

{let copied,error=cloneValue(self,value.patterns);if error!=Error.none {return result,error;}result.patterns=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::MatchArm)->blot_check_core::MatchArm,Error {

var result=default<blot_check_core::MatchArm>();

{let copied,error=cloneValue(self,value.rows);if error!=Error.none {return result,error;}result.rows=copied;}

{let copied,error=cloneValue(self,value.guard);if error!=Error.none {return result,error;}result.guard=copied;}

{let copied,error=cloneValue(self,value.body);if error!=Error.none {return result,error;}result.body=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::MatchInfo)->blot_check_core::MatchInfo,Error {

var result=default<blot_check_core::MatchInfo>();

{let copied,error=cloneValue(self,value.inputs);if error!=Error.none {return result,error;}result.inputs=copied;}

{let copied,error=cloneValue(self,value.arms);if error!=Error.none {return result,error;}result.arms=copied;}

{let copied,error=cloneValue(self,value.statement);if error!=Error.none {return result,error;}result.statement=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::UpdateInfo)->blot_check_core::UpdateInfo,Error {

var result=default<blot_check_core::UpdateInfo>();

{let copied,error=cloneValue(self,value.root);if error!=Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self,value.path);if error!=Error.none {return result,error;}result.path=copied;}

{let copied,error=cloneValue(self,value.value);if error!=Error.none {return result,error;}result.value=copied;}

{let copied,error=cloneValue(self,value.self_binding);if error!=Error.none {return result,error;}result.self_binding=copied;}

{let copied,error=cloneValue(self,value.selectors);if error!=Error.none {return result,error;}result.selectors=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::UpdateStep)->blot_check_core::UpdateStep,Error {

var result=default<blot_check_core::UpdateStep>();

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.projection);if error!=Error.none {return result,error;}result.projection=copied;}

{let copied,error=cloneValue(self,value.index);if error!=Error.none {return result,error;}result.index=copied;}

{let copied,error=cloneValue(self,value.source_type);if error!=Error.none {return result,error;}result.source_type=copied;}

{let copied,error=cloneValue(self,value.result_type);if error!=Error.none {return result,error;}result.result_type=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::UpdateKind)->blot_check_core::UpdateKind,Error {

match value {

blot_check_core::UpdateKind.field=>{
return blot_check_core::UpdateKind.field,Error.none;},

blot_check_core::UpdateKind.index=>{
return blot_check_core::UpdateKind.index,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::ClosureInfo)->blot_check_core::ClosureInfo,Error {

var result=default<blot_check_core::ClosureInfo>();

{let copied,error=cloneValue(self,value.qualifier);if error!=Error.none {return result,error;}result.qualifier=copied;}

{let copied,error=cloneValue(self,value.body);if error!=Error.none {return result,error;}result.body=copied;}

{let copied,error=cloneValue(self,value.parameter);if error!=Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self,value.captures);if error!=Error.none {return result,error;}result.captures=copied;}

{let copied,error=cloneValue(self,value.function_type);if error!=Error.none {return result,error;}result.function_type=copied;}

{let copied,error=cloneValue(self,value.closed_rows);if error!=Error.none {return result,error;}result.closed_rows=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Associated)->blot_check_core::Associated,Error {

var result=default<blot_check_core::Associated>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.member);if error!=Error.none {return result,error;}result.member=copied;}

{let copied,error=cloneValue(self,value.operator);if error!=Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Contract)->blot_check_core::Contract,Error {

var result=default<blot_check_core::Contract>();

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.row_variables);if error!=Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self,value.predicates);if error!=Error.none {return result,error;}result.predicates=copied;}

{let copied,error=cloneValue(self,value.members);if error!=Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self,value.requires_implementation);if error!=Error.none {return result,error;}result.requires_implementation=copied;}

{let copied,error=cloneValue(self,value.row_parameter_names);if error!=Error.none {return result,error;}result.row_parameter_names=copied;}

{let copied,error=cloneValue(self,value.row_parameters);if error!=Error.none {return result,error;}result.row_parameters=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::ContractMember)->blot_reuse_principal_interface::ContractMember,Error {

var result=default<blot_reuse_principal_interface::ContractMember>();

{let copied,error=cloneValue(self,value.contract);if error!=Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.root);if error!=Error.none {return result,error;}result.root=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::ContractMemberKind)->blot_reuse_principal_interface::ContractMemberKind,Error {

match value {

blot_reuse_principal_interface::ContractMemberKind.defined_type=>{
return blot_reuse_principal_interface::ContractMemberKind.defined_type,Error.none;},

blot_reuse_principal_interface::ContractMemberKind.abstract_type=>{
return blot_reuse_principal_interface::ContractMemberKind.abstract_type,Error.none;},

blot_reuse_principal_interface::ContractMemberKind.value=>{
return blot_reuse_principal_interface::ContractMemberKind.value,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Implementation)->blot_reuse_principal_interface::Implementation,Error {

var result=default<blot_reuse_principal_interface::Implementation>();

{let copied,error=cloneValue(self,value.origin_span);if error!=Error.none {return result,error;}result.origin_span=copied;}

{let copied,error=cloneValue(self,value.declaration);if error!=Error.none {return result,error;}result.declaration=copied;}

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.contract);if error!=Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self,value.head);if error!=Error.none {return result,error;}result.head=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.parameter_names);if error!=Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self,value.row_variables);if error!=Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self,value.row_parameter_names);if error!=Error.none {return result,error;}result.row_parameter_names=copied;}

{let copied,error=cloneValue(self,value.row_parameters);if error!=Error.none {return result,error;}result.row_parameters=copied;}

{let copied,error=cloneValue(self,value.predicates);if error!=Error.none {return result,error;}result.predicates=copied;}

{let copied,error=cloneValue(self,value.members);if error!=Error.none {return result,error;}result.members=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::ImplementationMember)->blot_reuse_principal_interface::ImplementationMember,Error {

var result=default<blot_reuse_principal_interface::ImplementationMember>();

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.root);if error!=Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::ImplementationMemberKind)->blot_reuse_principal_interface::ImplementationMemberKind,Error {

match value {

blot_reuse_principal_interface::ImplementationMemberKind.type_=>{
return blot_reuse_principal_interface::ImplementationMemberKind.type_,Error.none;},

blot_reuse_principal_interface::ImplementationMemberKind.value=>{
return blot_reuse_principal_interface::ImplementationMemberKind.value,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::ExternalTarget)->blot_reuse_principal_interface::ExternalTarget,Error {

var result=default<blot_reuse_principal_interface::ExternalTarget>();

{let copied,error=cloneValue(self,value.unit);if error!=Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::MemberTemplate)->blot_reuse_principal_interface::MemberTemplate,Error {

var result=default<blot_reuse_principal_interface::MemberTemplate>();

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.contract);if error!=Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.arguments);if error!=Error.none {return result,error;}result.arguments=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::SelectedProof)->blot_reuse_principal_interface::SelectedProof,Error {

var result=default<blot_reuse_principal_interface::SelectedProof>();

{let copied,error=cloneValue(self,value.predicate_target);if error!=Error.none {return result,error;}result.predicate_target=copied;}

{let copied,error=cloneValue(self,value.context);if error!=Error.none {return result,error;}result.context=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.predicate);if error!=Error.none {return result,error;}result.predicate=copied;}

{let copied,error=cloneValue(self,value.implementation);if error!=Error.none {return result,error;}result.implementation=copied;}

{let copied,error=cloneValue(self,value.contract);if error!=Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self,value.arguments);if error!=Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self,value.members);if error!=Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self,value.prerequisites);if error!=Error.none {return result,error;}result.prerequisites=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::SelectedProofKind)->blot_reuse_principal_interface::SelectedProofKind,Error {

match value {

blot_reuse_principal_interface::SelectedProofKind.implementation=>{
return blot_reuse_principal_interface::SelectedProofKind.implementation,Error.none;},

blot_reuse_principal_interface::SelectedProofKind.predicate=>{
return blot_reuse_principal_interface::SelectedProofKind.predicate,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::SelectedUse)->blot_check_core::SelectedUse,Error {

var result=default<blot_check_core::SelectedUse>();

{let copied,error=cloneValue(self,value.node);if error!=Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self,value.proof);if error!=Error.none {return result,error;}result.proof=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::DictionarySelection)->blot_check_core::DictionarySelection,Error {

var result=default<blot_check_core::DictionarySelection>();

{let copied,error=cloneValue(self,value.owner);if error!=Error.none {return result,error;}result.owner=copied;}

{let copied,error=cloneValue(self,value.quantifier);if error!=Error.none {return result,error;}result.quantifier=copied;}

{let copied,error=cloneValue(self,value.goal);if error!=Error.none {return result,error;}result.goal=copied;}

{let copied,error=cloneValue(self,value.proof);if error!=Error.none {return result,error;}result.proof=copied;}

{let copied,error=cloneValue(self,value.members);if error!=Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self,value.contents);if error!=Error.none {return result,error;}result.contents=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::DictionaryProof)->blot_check_core::DictionaryProof,Error {

match value {

blot_check_core::DictionaryProof.selected payload=>{
let value,error_value=cloneValue(self,payload.value);if error_value!=Error.none {return default<blot_check_core::DictionaryProof>(),error_value;}
return blot_check_core::DictionaryProof.selected {value:value},Error.none;},

blot_check_core::DictionaryProof.given payload=>{
let value,error_value=cloneValue(self,payload.value);if error_value!=Error.none {return default<blot_check_core::DictionaryProof>(),error_value;}
return blot_check_core::DictionaryProof.given {value:value},Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::DictionaryGiven)->blot_check_core::DictionaryGiven,Error {

var result=default<blot_check_core::DictionaryGiven>();

{let copied,error=cloneValue(self,value.opening);if error!=Error.none {return result,error;}result.opening=copied;}

{let copied,error=cloneValue(self,value.introduction);if error!=Error.none {return result,error;}result.introduction=copied;}

{let copied,error=cloneValue(self,value.quantifier);if error!=Error.none {return result,error;}result.quantifier=copied;}

{let copied,error=cloneValue(self,value.goal);if error!=Error.none {return result,error;}result.goal=copied;}

{let copied,error=cloneValue(self,value.arguments);if error!=Error.none {return result,error;}result.arguments=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::DictionaryUse)->blot_check_core::DictionaryUse,Error {

var result=default<blot_check_core::DictionaryUse>();

{let copied,error=cloneValue(self,value.node);if error!=Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self,value.opening);if error!=Error.none {return result,error;}result.opening=copied;}

{let copied,error=cloneValue(self,value.introduction);if error!=Error.none {return result,error;}result.introduction=copied;}

{let copied,error=cloneValue(self,value.quantifier);if error!=Error.none {return result,error;}result.quantifier=copied;}

{let copied,error=cloneValue(self,value.goal);if error!=Error.none {return result,error;}result.goal=copied;}

{let copied,error=cloneValue(self,value.member);if error!=Error.none {return result,error;}result.member=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Primitive)->blot_check_core::Primitive,Error {

var result=default<blot_check_core::Primitive>();

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.op);if error!=Error.none {return result,error;}result.op=copied;}

{let copied,error=cloneValue(self,value.array_op);if error!=Error.none {return result,error;}result.array_op=copied;}

{let copied,error=cloneValue(self,value.arity);if error!=Error.none {return result,error;}result.arity=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::PrimitiveKind)->blot_check_core::PrimitiveKind,Error {

match value {

blot_check_core::PrimitiveKind.scalar=>{
return blot_check_core::PrimitiveKind.scalar,Error.none;},

blot_check_core::PrimitiveKind.array=>{
return blot_check_core::PrimitiveKind.array,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_backend_collection_ops::Op)->blot_backend_collection_ops::Op,Error {

match value {

blot_backend_collection_ops::Op.length=>{
return blot_backend_collection_ops::Op.length,Error.none;},

blot_backend_collection_ops::Op.get=>{
return blot_backend_collection_ops::Op.get,Error.none;},

blot_backend_collection_ops::Op.set=>{
return blot_backend_collection_ops::Op.set,Error.none;},

blot_backend_collection_ops::Op.fill=>{
return blot_backend_collection_ops::Op.fill,Error.none;},

blot_backend_collection_ops::Op.generate=>{
return blot_backend_collection_ops::Op.generate,Error.none;},

blot_backend_collection_ops::Op.append=>{
return blot_backend_collection_ops::Op.append,Error.none;},

blot_backend_collection_ops::Op.prepend=>{
return blot_backend_collection_ops::Op.prepend,Error.none;},

blot_backend_collection_ops::Op.identity=>{
return blot_backend_collection_ops::Op.identity,Error.none;},

blot_backend_collection_ops::Op.convert=>{
return blot_backend_collection_ops::Op.convert,Error.none;},

blot_backend_collection_ops::Op.cursor=>{
return blot_backend_collection_ops::Op.cursor,Error.none;},

blot_backend_collection_ops::Op.cursor_has=>{
return blot_backend_collection_ops::Op.cursor_has,Error.none;},

blot_backend_collection_ops::Op.cursor_value=>{
return blot_backend_collection_ops::Op.cursor_value,Error.none;},

blot_backend_collection_ops::Op.cursor_advance=>{
return blot_backend_collection_ops::Op.cursor_advance,Error.none;},

blot_backend_collection_ops::Op.concat=>{
return blot_backend_collection_ops::Op.concat,Error.none;},

blot_backend_collection_ops::Op.slice=>{
return blot_backend_collection_ops::Op.slice,Error.none;},

blot_backend_collection_ops::Op.simd_load=>{
return blot_backend_collection_ops::Op.simd_load,Error.none;},

blot_backend_collection_ops::Op.simd_store=>{
return blot_backend_collection_ops::Op.simd_store,Error.none;},

blot_backend_collection_ops::Op.flatten=>{
return blot_backend_collection_ops::Op.flatten,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::LoopInfo)->blot_check_core::LoopInfo,Error {

var result=default<blot_check_core::LoopInfo>();

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.first);if error!=Error.none {return result,error;}result.first=copied;}

{let copied,error=cloneValue(self,value.end);if error!=Error.none {return result,error;}result.end=copied;}

{let copied,error=cloneValue(self,value.pattern);if error!=Error.none {return result,error;}result.pattern=copied;}

{let copied,error=cloneValue(self,value.body);if error!=Error.none {return result,error;}result.body=copied;}

{let copied,error=cloneValue(self,value.carries);if error!=Error.none {return result,error;}result.carries=copied;}

{let copied,error=cloneValue(self,value.can_exit);if error!=Error.none {return result,error;}result.can_exit=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::LoopKind)->blot_check_core::LoopKind,Error {

match value {

blot_check_core::LoopKind.forever=>{
return blot_check_core::LoopKind.forever,Error.none;},

blot_check_core::LoopKind.range=>{
return blot_check_core::LoopKind.range,Error.none;},

blot_check_core::LoopKind.array=>{
return blot_check_core::LoopKind.array,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::LoopCarry)->blot_check_core::LoopCarry,Error {

var result=default<blot_check_core::LoopCarry>();

{let copied,error=cloneValue(self,value.incoming);if error!=Error.none {return result,error;}result.incoming=copied;}

{let copied,error=cloneValue(self,value.iteration);if error!=Error.none {return result,error;}result.iteration=copied;}

{let copied,error=cloneValue(self,value.backedge);if error!=Error.none {return result,error;}result.backedge=copied;}

{let copied,error=cloneValue(self,value.outgoing);if error!=Error.none {return result,error;}result.outgoing=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::ResolverInfo)->blot_check_core::ResolverInfo,Error {

var result=default<blot_check_core::ResolverInfo>();

{let copied,error=cloneValue(self,value.operation);if error!=Error.none {return result,error;}result.operation=copied;}

{let copied,error=cloneValue(self,value.resolver);if error!=Error.none {return result,error;}result.resolver=copied;}

{let copied,error=cloneValue(self,value.arguments);if error!=Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self,value.member);if error!=Error.none {return result,error;}result.member=copied;}

{let copied,error=cloneValue(self,value.method);if error!=Error.none {return result,error;}result.method=copied;}

{let copied,error=cloneValue(self,value.method_type);if error!=Error.none {return result,error;}result.method_type=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::ResolverOperation)->blot_check_core::ResolverOperation,Error {

match value {

blot_check_core::ResolverOperation.monad=>{
return blot_check_core::ResolverOperation.monad,Error.none;},

blot_check_core::ResolverOperation.pure=>{
return blot_check_core::ResolverOperation.pure,Error.none;},

blot_check_core::ResolverOperation.bind=>{
return blot_check_core::ResolverOperation.bind,Error.none;},

blot_check_core::ResolverOperation.forward=>{
return blot_check_core::ResolverOperation.forward,Error.none;},

blot_check_core::ResolverOperation.iterate=>{
return blot_check_core::ResolverOperation.iterate,Error.none;},

blot_check_core::ResolverOperation.run=>{
return blot_check_core::ResolverOperation.run,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_check_core::OperationValue)->blot_check_core::OperationValue,Error {

var result=default<blot_check_core::OperationValue>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.arguments);if error!=Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self,value.signature);if error!=Error.none {return result,error;}result.signature=copied;}

{let copied,error=cloneValue(self,value.witness);if error!=Error.none {return result,error;}result.witness=copied;}

{let copied,error=cloneValue(self,value.witness_result);if error!=Error.none {return result,error;}result.witness_result=copied;}

{let copied,error=cloneValue(self,value.instance);if error!=Error.none {return result,error;}result.instance=copied;}

{let copied,error=cloneValue(self,value.capability);if error!=Error.none {return result,error;}result.capability=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::HandleEffects)->blot_check_core::HandleEffects,Error {

var result=default<blot_check_core::HandleEffects>();

{let copied,error=cloneValue(self,value.node);if error!=Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self,value.first);if error!=Error.none {return result,error;}result.first=copied;}

{let copied,error=cloneValue(self,value.second);if error!=Error.none {return result,error;}result.second=copied;}

{let copied,error=cloneValue(self,value.extended);if error!=Error.none {return result,error;}result.extended=copied;}

{let copied,error=cloneValue(self,value.residual);if error!=Error.none {return result,error;}result.residual=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Diagnostic)->blot_check_core::Diagnostic,Error {

var result=default<blot_check_core::Diagnostic>();

{let copied,error=cloneValue(self,value.code);if error!=Error.none {return result,error;}result.code=copied;}

{let copied,error=cloneValue(self,value.span);if error!=Error.none {return result,error;}result.span=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_core::Code)->blot_check_core::Code,Error {

match value {

blot_check_core::Code.unchecked=>{
return blot_check_core::Code.unchecked,Error.none;},

blot_check_core::Code.unsupported=>{
return blot_check_core::Code.unsupported,Error.none;},

blot_check_core::Code.unresolved_binding=>{
return blot_check_core::Code.unresolved_binding,Error.none;},

blot_check_core::Code.invalid_call=>{
return blot_check_core::Code.invalid_call,Error.none;},

blot_check_core::Code.complexity=>{
return blot_check_core::Code.complexity,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Interface)->blot_reuse_principal_interface::Interface,Error {

var result=default<blot_reuse_principal_interface::Interface>();

{let copied,error=cloneValue(self,value.has_rank_contracts);if error!=Error.none {return result,error;}result.has_rank_contracts=copied;}

{let copied,error=cloneValue(self,value.has_usage_contracts);if error!=Error.none {return result,error;}result.has_usage_contracts=copied;}

{let copied,error=cloneValue(self,value.has_numeric_proofs);if error!=Error.none {return result,error;}result.has_numeric_proofs=copied;}

{let copied,error=cloneValue(self,value.proof_contracts);if error!=Error.none {return result,error;}result.proof_contracts=copied;}

{let copied,error=cloneValue(self,value.capability_contracts);if error!=Error.none {return result,error;}result.capability_contracts=copied;}

{let copied,error=cloneValue(self,value.unit);if error!=Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self,value.graph);if error!=Error.none {return result,error;}result.graph=copied;}

{let copied,error=cloneValue(self,value.patterns);if error!=Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self,value.bindings);if error!=Error.none {return result,error;}result.bindings=copied;}

{let copied,error=cloneValue(self,value.obligations);if error!=Error.none {return result,error;}result.obligations=copied;}

{let copied,error=cloneValue(self,value.obligation_spans);if error!=Error.none {return result,error;}result.obligation_spans=copied;}

{let copied,error=cloneValue(self,value.nominals);if error!=Error.none {return result,error;}result.nominals=copied;}

{let copied,error=cloneValue(self,value.constructors);if error!=Error.none {return result,error;}result.constructors=copied;}

{let copied,error=cloneValue(self,value.effect_families);if error!=Error.none {return result,error;}result.effect_families=copied;}

{let copied,error=cloneValue(self,value.effect_templates);if error!=Error.none {return result,error;}result.effect_templates=copied;}

{let copied,error=cloneValue(self,value.associated);if error!=Error.none {return result,error;}result.associated=copied;}

{let copied,error=cloneValue(self,value.contracts);if error!=Error.none {return result,error;}result.contracts=copied;}

{let copied,error=cloneValue(self,value.contract_predicates);if error!=Error.none {return result,error;}result.contract_predicates=copied;}

{let copied,error=cloneValue(self,value.contract_members);if error!=Error.none {return result,error;}result.contract_members=copied;}

{let copied,error=cloneValue(self,value.implementations);if error!=Error.none {return result,error;}result.implementations=copied;}

{let copied,error=cloneValue(self,value.implementation_predicates);if error!=Error.none {return result,error;}result.implementation_predicates=copied;}

{let copied,error=cloneValue(self,value.implementation_members);if error!=Error.none {return result,error;}result.implementation_members=copied;}

{let copied,error=cloneValue(self,value.member_templates);if error!=Error.none {return result,error;}result.member_templates=copied;}

{let copied,error=cloneValue(self,value.selected_proofs);if error!=Error.none {return result,error;}result.selected_proofs=copied;}

{let copied,error=cloneValue(self,value.selected_members);if error!=Error.none {return result,error;}result.selected_members=copied;}

{let copied,error=cloneValue(self,value.selected_edges);if error!=Error.none {return result,error;}result.selected_edges=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_frozen_types::Graph)->blot_check_frozen_types::Graph,Error {

var result=default<blot_check_frozen_types::Graph>();

{let copied,error=cloneValue(self,value.nodes);if error!=Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self,value.extra);if error!=Error.none {return result,error;}result.extra=copied;}

{let copied,error=cloneValue(self,value.rows);if error!=Error.none {return result,error;}result.rows=copied;}

{let copied,error=cloneValue(self,value.labels);if error!=Error.none {return result,error;}result.labels=copied;}

{let copied,error=cloneValue(self,value.operations);if error!=Error.none {return result,error;}result.operations=copied;}

{let copied,error=cloneValue(self,value.row_variable_count);if error!=Error.none {return result,error;}result.row_variable_count=copied;}

{let copied,error=cloneValue(self,value.quantifier_goals);if error!=Error.none {return result,error;}result.quantifier_goals=copied;}

{let copied,error=cloneValue(self,value.quantifier_obligations);if error!=Error.none {return result,error;}result.quantifier_obligations=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_frozen_types::PatternGraph)->blot_check_frozen_types::PatternGraph,Error {

var result=default<blot_check_frozen_types::PatternGraph>();

{let copied,error=cloneValue(self,value.nodes);if error!=Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self,value.extra);if error!=Error.none {return result,error;}result.extra=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_parameter_patterns::Node)->blot_check_parameter_patterns::Node,Error {

var result=default<blot_check_parameter_patterns::Node>();

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.a);if error!=Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self,value.b);if error!=Error.none {return result,error;}result.b=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_check_parameter_patterns::Kind)->blot_check_parameter_patterns::Kind,Error {

match value {

blot_check_parameter_patterns::Kind.binding=>{
return blot_check_parameter_patterns::Kind.binding,Error.none;},

blot_check_parameter_patterns::Kind.tuple=>{
return blot_check_parameter_patterns::Kind.tuple,Error.none;},

blot_check_parameter_patterns::Kind.array=>{
return blot_check_parameter_patterns::Kind.array,Error.none;},

blot_check_parameter_patterns::Kind.record=>{
return blot_check_parameter_patterns::Kind.record,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Binding)->blot_reuse_principal_interface::Binding,Error {

var result=default<blot_reuse_principal_interface::Binding>();

{let copied,error=cloneValue(self,value.capability_flow);if error!=Error.none {return result,error;}result.capability_flow=copied;}

{let copied,error=cloneValue(self,value.capability_parameters);if error!=Error.none {return result,error;}result.capability_parameters=copied;}

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.named_function);if error!=Error.none {return result,error;}result.named_function=copied;}

{let copied,error=cloneValue(self,value.ty);if error!=Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self,value.scheme);if error!=Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self,value.external);if error!=Error.none {return result,error;}result.external=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Nominal)->blot_reuse_principal_interface::Nominal,Error {

var result=default<blot_reuse_principal_interface::Nominal>();

{let copied,error=cloneValue(self,value.affine);if error!=Error.none {return result,error;}result.affine=copied;}

{let copied,error=cloneValue(self,value.has_usage);if error!=Error.none {return result,error;}result.has_usage=copied;}

{let copied,error=cloneValue(self,value.closed_storage);if error!=Error.none {return result,error;}result.closed_storage=copied;}

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.is_opaque);if error!=Error.none {return result,error;}result.is_opaque=copied;}

{let copied,error=cloneValue(self,value.storage);if error!=Error.none {return result,error;}result.storage=copied;}

{let copied,error=cloneValue(self,value.declaration);if error!=Error.none {return result,error;}result.declaration=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.patterns);if error!=Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self,value.parameter_names);if error!=Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self,value.constructors);if error!=Error.none {return result,error;}result.constructors=copied;}

{let copied,error=cloneValue(self,value.alias);if error!=Error.none {return result,error;}result.alias=copied;}

{let copied,error=cloneValue(self,value.alias_rows);if error!=Error.none {return result,error;}result.alias_rows=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Constructor)->blot_reuse_principal_interface::Constructor,Error {

var result=default<blot_reuse_principal_interface::Constructor>();

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.nominal);if error!=Error.none {return result,error;}result.nominal=copied;}

{let copied,error=cloneValue(self,value.tag);if error!=Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.scheme);if error!=Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self,value.payload);if error!=Error.none {return result,error;}result.payload=copied;}

{let copied,error=cloneValue(self,value.declared_record);if error!=Error.none {return result,error;}result.declared_record=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::EffectFamily)->blot_reuse_principal_interface::EffectFamily,Error {

var result=default<blot_reuse_principal_interface::EffectFamily>();

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.callable);if error!=Error.none {return result,error;}result.callable=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.patterns);if error!=Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self,value.parameter_names);if error!=Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self,value.operations);if error!=Error.none {return result,error;}result.operations=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::EffectTemplate)->blot_reuse_principal_interface::EffectTemplate,Error {

var result=default<blot_reuse_principal_interface::EffectTemplate>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.family);if error!=Error.none {return result,error;}result.family=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.parameter);if error!=Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self,value.result);if error!=Error.none {return result,error;}result.result=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Associated)->blot_reuse_principal_interface::Associated,Error {

var result=default<blot_reuse_principal_interface::Associated>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.member);if error!=Error.none {return result,error;}result.member=copied;}

{let copied,error=cloneValue(self,value.operator);if error!=Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self,value.binding);if error!=Error.none {return result,error;}result.binding=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_principal_interface::Contract)->blot_reuse_principal_interface::Contract,Error {

var result=default<blot_reuse_principal_interface::Contract>();

{let copied,error=cloneValue(self,value.declaration);if error!=Error.none {return result,error;}result.declaration=copied;}

{let copied,error=cloneValue(self,value.private);if error!=Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.parameters);if error!=Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self,value.variables);if error!=Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self,value.patterns);if error!=Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self,value.parameter_names);if error!=Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self,value.row_variables);if error!=Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self,value.row_parameter_names);if error!=Error.none {return result,error;}result.row_parameter_names=copied;}

{let copied,error=cloneValue(self,value.row_parameters);if error!=Error.none {return result,error;}result.row_parameters=copied;}

{let copied,error=cloneValue(self,value.predicates);if error!=Error.none {return result,error;}result.predicates=copied;}

{let copied,error=cloneValue(self,value.members);if error!=Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self,value.requires_implementation);if error!=Error.none {return result,error;}result.requires_implementation=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::Module)->blot_reuse_frozen_dependency::Module,Error {

var result=default<blot_reuse_frozen_dependency::Module>();

{let copied,error=cloneValue(self,value.identity);if error!=Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self,value.imports);if error!=Error.none {return result,error;}result.imports=copied;}

{let copied,error=cloneValue(self,value.implicit_prelude);if error!=Error.none {return result,error;}result.implicit_prelude=copied;}

{let copied,error=cloneValue(self,value.source_imports);if error!=Error.none {return result,error;}result.source_imports=copied;}

{let copied,error=cloneValue(self,value.core);if error!=Error.none {return result,error;}result.core=copied;}

{let copied,error=cloneValue(self,value.interface);if error!=Error.none {return result,error;}result.interface=copied;}

{let copied,error=cloneValue(self,value.exports);if error!=Error.none {return result,error;}result.exports=copied;}

{let copied,error=cloneValue(self,value.fixities);if error!=Error.none {return result,error;}result.fixities=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::Identity)->blot_reuse_frozen_dependency::Identity,Error {

var result=default<blot_reuse_frozen_dependency::Identity>();

{let copied,error=cloneValue(self,value.normalized_path);if error!=Error.none {return result,error;}result.normalized_path=copied;}

{let copied,error=cloneValue(self,value.source_digest);if error!=Error.none {return result,error;}result.source_digest=copied;}

{let copied,error=cloneValue(self,value.source_bytes);if error!=Error.none {return result,error;}result.source_bytes=copied;}

{let copied,error=cloneValue(self,value.prelude);if error!=Error.none {return result,error;}result.prelude=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::ImportResolution)->blot_reuse_frozen_dependency::ImportResolution,Error {

var result=default<blot_reuse_frozen_dependency::ImportResolution>();

{let copied,error=cloneValue(self,value.path);if error!=Error.none {return result,error;}result.path=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::Export)->blot_reuse_frozen_dependency::Export,Error {

var result=default<blot_reuse_frozen_dependency::Export>();

{let copied,error=cloneValue(self,value.name);if error!=Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self,value.kind);if error!=Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self,value.catalog);if error!=Error.none {return result,error;}result.catalog=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::ExportKind)->blot_reuse_frozen_dependency::ExportKind,Error {

match value {

blot_reuse_frozen_dependency::ExportKind.value=>{
return blot_reuse_frozen_dependency::ExportKind.value,Error.none;},

blot_reuse_frozen_dependency::ExportKind.nominal=>{
return blot_reuse_frozen_dependency::ExportKind.nominal,Error.none;},

blot_reuse_frozen_dependency::ExportKind.constructor=>{
return blot_reuse_frozen_dependency::ExportKind.constructor,Error.none;},

blot_reuse_frozen_dependency::ExportKind.effect_family=>{
return blot_reuse_frozen_dependency::ExportKind.effect_family,Error.none;},

blot_reuse_frozen_dependency::ExportKind.contract=>{
return blot_reuse_frozen_dependency::ExportKind.contract,Error.none;},

blot_reuse_frozen_dependency::ExportKind.implementation=>{
return blot_reuse_frozen_dependency::ExportKind.implementation,Error.none;},

}

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::Fixity)->blot_reuse_frozen_dependency::Fixity,Error {

var result=default<blot_reuse_frozen_dependency::Fixity>();

{let copied,error=cloneValue(self,value.operator);if error!=Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self,value.target);if error!=Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self,value.precedence);if error!=Error.none {return result,error;}result.precedence=copied;}

{let copied,error=cloneValue(self,value.association);if error!=Error.none {return result,error;}result.association=copied;}

{let copied,error=cloneValue(self,value.named);if error!=Error.none {return result,error;}result.named=copied;}

{let copied,error=cloneValue(self,value.producer);if error!=Error.none {return result,error;}result.producer=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::FrozenDependency)->blot_reuse_frozen_dependency::FrozenDependency,Error {

var result=default<blot_reuse_frozen_dependency::FrozenDependency>();

{let copied,error=cloneValue(self,value.symbols);if error!=Error.none {return result,error;}result.symbols=copied;}

{let copied,error=cloneValue(self,value.modules);if error!=Error.none {return result,error;}result.modules=copied;}

return result,Error.none;

}

fn cloneValue(self:Owner&,value:blot_reuse_frozen_dependency::Symbol)->blot_reuse_frozen_dependency::Symbol,Error {

var result=default<blot_reuse_frozen_dependency::Symbol>();

{let copied,error=cloneValue(self,value.text);if error!=Error.none {return result,error;}result.text=copied;}

return result,Error.none;

}

fn clone(value:const blot_check_core::Module&)->Owned<blot_check_core::Module>,Error {
 var owner,error=init();if error!=Error.none {return default<Owned<blot_check_core::Module>>(),error;}
 let result,error=cloneValue(owner,value);if error!=Error.none {owner.deinit();return default<Owned<blot_check_core::Module>>(),error;}return Owned<blot_check_core::Module> {result,owner},Error.none;
}

fn clone(value:const blot_reuse_principal_interface::Interface&)->Owned<blot_reuse_principal_interface::Interface>,Error {
 var owner,error=init();if error!=Error.none {return default<Owned<blot_reuse_principal_interface::Interface>>(),error;}
 let result,error=cloneValue(owner,value);if error!=Error.none {owner.deinit();return default<Owned<blot_reuse_principal_interface::Interface>>(),error;}return Owned<blot_reuse_principal_interface::Interface> {result,owner},Error.none;
}

fn clone(value:const blot_reuse_frozen_dependency::Module&)->Owned<blot_reuse_frozen_dependency::Module>,Error {
 var owner,error=init();if error!=Error.none {return default<Owned<blot_reuse_frozen_dependency::Module>>(),error;}
 let result,error=cloneValue(owner,value);if error!=Error.none {owner.deinit();return default<Owned<blot_reuse_frozen_dependency::Module>>(),error;}return Owned<blot_reuse_frozen_dependency::Module> {result,owner},Error.none;
}

fn clone(value:const blot_reuse_frozen_dependency::FrozenDependency&)->Owned<blot_reuse_frozen_dependency::FrozenDependency>,Error {
 var owner,error=init();if error!=Error.none {return default<Owned<blot_reuse_frozen_dependency::FrozenDependency>>(),error;}
 let result,error=cloneValue(owner,value);if error!=Error.none {owner.deinit();return default<Owned<blot_reuse_frozen_dependency::FrozenDependency>>(),error;}return Owned<blot_reuse_frozen_dependency::FrozenDependency> {result,owner},Error.none;
}
