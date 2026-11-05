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
import backend.runtime_identity;
import reuse.entry_frontend_cutoff;
import support.native;
import support.option;

type Error=blot_error::Error;
struct Owner {lease:u32=0,generation:u64=0}
struct Owned<T> {value:T,owner:Owner=Owner {..}}
type HeaderPath=const u8[:];
type HeaderDigest=u8[32];

enum Run {
run_header_module {values:blot_check_core::Module[:]},
run_header_path {values:HeaderPath[:]},
run_header_digest {values:HeaderDigest[:]},
run_header_name {values:blot_backend_runtime_identity::Name[:]},
run_header_import {values:blot_reuse_entry_frontend_cutoff::Import[:]},
run_header_owner {values:Owner[:]},
run_bool {values:bool[:]},
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

struct Lease {head:u32=0,generation:u64=0,live:bool=false,references:u64=1}

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

fn valid(self_:const Owner&)->bool {return self_.lease!=0&&self_.lease-1<leases.len&&leases[self_.lease-1].live&&leases[self_.lease-1].generation==self_.generation;}
fn init()->Owner,Error {if leases.len>=0xffffffff {return Owner {..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=leases.alloc_index(Lease {generation:generation,live:true, ..});return Owner {(at+1) as u32,generation, ..},blot_error::Error.none;}
fn remember(self_:Owner&,value:Run)->Error {assert(unique(self_));if links.len>=0xffffffff {return blot_error::Error.out_of_memory;}let head=leases[self_.lease-1].head;let at=links.alloc_index(Link {value,head, ..});leases[self_.lease-1].head=(at+1) as u32;return blot_error::Error.none;}
fn deinit(self_:Owner&) {if self_.lease==0 {return;}assert(valid(self_));let owner=self_.lease-1;assert(leases[owner].references!=0);leases[owner].references-=1;if leases[owner].references!=0 {self_=Owner {..};return;}var next=leases[owner].head;while next!=0 {let at=next-1;let link=links[at];next=link.next;match link.value {
run_header_module run=>{pool_header_module.free_slice(run.values);},
run_header_path run=>{pool_header_path.free_slice(run.values);},
run_header_digest run=>{pool_header_digest.free_slice(run.values);},
run_header_name run=>{pool_header_name.free_slice(run.values);},
run_header_import run=>{pool_header_import.free_slice(run.values);},
run_header_owner run=>{pool_header_owner.free_slice(run.values);},
run_bool run=>{pool_bool.free_slice(run.values);},


run_u32 run=>{pool_u32.free_slice(run.values);},

run_blot_check_numeric_proof_terms__Kind run=>{pool_blot_check_numeric_proof_terms__Kind.free_slice(run.values);},

run_blot_check_numeric_proof_terms__Term run=>{pool_blot_check_numeric_proof_terms__Term.free_slice(run.values);},

run_blot_check_numeric_proof_contracts__Requirement run=>{pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run.values);},

run_blot_check_numeric_proof_headers__Named run=>{pool_blot_check_numeric_proof_headers__Named.free_slice(run.values);},

run_blot_check_capability_contracts__Term run=>{pool_blot_check_capability_contracts__Term.free_slice(run.values);},

run_blot_check_capability_contracts__Binding run=>{pool_blot_check_capability_contracts__Binding.free_slice(run.values);},

run_blot_check_core__FieldName run=>{pool_blot_check_core__FieldName.free_slice(run.values);},

run_blot_check_core__RuntimeName run=>{pool_blot_check_core__RuntimeName.free_slice(run.values);},

run_blot_check_core__DeclarationDependencies run=>{pool_blot_check_core__DeclarationDependencies.free_slice(run.values);},

run_blot_check_core__BindingRef run=>{pool_blot_check_core__BindingRef.free_slice(run.values);},

run_blot_check_core__DependencyMember run=>{pool_blot_check_core__DependencyMember.free_slice(run.values);},

run_blot_check_core__ErasedDeclarationReference run=>{pool_blot_check_core__ErasedDeclarationReference.free_slice(run.values);},

run_blot_check_core__RequestLoopInfo run=>{pool_blot_check_core__RequestLoopInfo.free_slice(run.values);},

run_blot_check_core__RequestArm run=>{pool_blot_check_core__RequestArm.free_slice(run.values);},

run_blot_check_types__Node run=>{pool_blot_check_types__Node.free_slice(run.values);},

run_blot_check_effects__Row run=>{pool_blot_check_effects__Row.free_slice(run.values);},

run_blot_check_types__Operation run=>{pool_blot_check_types__Operation.free_slice(run.values);},

run_blot_check_types__QuantifierGoals run=>{pool_blot_check_types__QuantifierGoals.free_slice(run.values);},

run_blot_check_types__Obligation run=>{pool_blot_check_types__Obligation.free_slice(run.values);},

run_blot_check_core__Node run=>{pool_blot_check_core__Node.free_slice(run.values);},

run_blot_parse_ast__Span run=>{pool_blot_parse_ast__Span.free_slice(run.values);},

run_blot_check_core__Binding run=>{pool_blot_check_core__Binding.free_slice(run.values);},

run_blot_check_core__Body run=>{pool_blot_check_core__Body.free_slice(run.values);},

run_blot_check_core__Parameter run=>{pool_blot_check_core__Parameter.free_slice(run.values);},

run_blot_check_core__CallInfo run=>{pool_blot_check_core__CallInfo.free_slice(run.values);},

run_blot_check_core__Merge run=>{pool_blot_check_core__Merge.free_slice(run.values);},

run_blot_check_core__List run=>{pool_blot_check_core__List.free_slice(run.values);},

run_u8 run=>{pool_u8.free_slice(run.values);},

run_blot_check_core__Obligation run=>{pool_blot_check_core__Obligation.free_slice(run.values);},

run_blot_check_core__Nominal run=>{pool_blot_check_core__Nominal.free_slice(run.values);},

run_blot_check_core__OperationName run=>{pool_blot_check_core__OperationName.free_slice(run.values);},

run_blot_check_core__Constructor run=>{pool_blot_check_core__Constructor.free_slice(run.values);},

run_blot_check_core__Projection run=>{pool_blot_check_core__Projection.free_slice(run.values);},

run_blot_check_core__ProjectionVariant run=>{pool_blot_check_core__ProjectionVariant.free_slice(run.values);},

run_blot_check_core__Pattern run=>{pool_blot_check_core__Pattern.free_slice(run.values);},

run_blot_check_core__PatternRow run=>{pool_blot_check_core__PatternRow.free_slice(run.values);},

run_blot_check_core__MatchArm run=>{pool_blot_check_core__MatchArm.free_slice(run.values);},

run_blot_check_core__MatchInfo run=>{pool_blot_check_core__MatchInfo.free_slice(run.values);},

run_blot_check_core__UpdateInfo run=>{pool_blot_check_core__UpdateInfo.free_slice(run.values);},

run_blot_check_core__UpdateStep run=>{pool_blot_check_core__UpdateStep.free_slice(run.values);},

run_blot_check_core__ClosureInfo run=>{pool_blot_check_core__ClosureInfo.free_slice(run.values);},

run_blot_check_core__Associated run=>{pool_blot_check_core__Associated.free_slice(run.values);},

run_blot_check_core__Contract run=>{pool_blot_check_core__Contract.free_slice(run.values);},

run_blot_reuse_principal_interface__ContractMember run=>{pool_blot_reuse_principal_interface__ContractMember.free_slice(run.values);},

run_blot_reuse_principal_interface__Implementation run=>{pool_blot_reuse_principal_interface__Implementation.free_slice(run.values);},

run_blot_reuse_principal_interface__ImplementationMember run=>{pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run.values);},

run_blot_reuse_principal_interface__MemberTemplate run=>{pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run.values);},

run_blot_reuse_principal_interface__SelectedProof run=>{pool_blot_reuse_principal_interface__SelectedProof.free_slice(run.values);},

run_blot_check_core__SelectedUse run=>{pool_blot_check_core__SelectedUse.free_slice(run.values);},

run_blot_check_core__DictionarySelection run=>{pool_blot_check_core__DictionarySelection.free_slice(run.values);},

run_blot_check_core__DictionaryUse run=>{pool_blot_check_core__DictionaryUse.free_slice(run.values);},

run_blot_check_core__Primitive run=>{pool_blot_check_core__Primitive.free_slice(run.values);},

run_blot_check_core__LoopInfo run=>{pool_blot_check_core__LoopInfo.free_slice(run.values);},

run_blot_check_core__LoopCarry run=>{pool_blot_check_core__LoopCarry.free_slice(run.values);},

run_blot_check_core__ResolverInfo run=>{pool_blot_check_core__ResolverInfo.free_slice(run.values);},

run_blot_check_core__OperationValue run=>{pool_blot_check_core__OperationValue.free_slice(run.values);},

run_blot_check_core__HandleEffects run=>{pool_blot_check_core__HandleEffects.free_slice(run.values);},

run_blot_check_core__Diagnostic run=>{pool_blot_check_core__Diagnostic.free_slice(run.values);},

run_blot_check_parameter_patterns__Node run=>{pool_blot_check_parameter_patterns__Node.free_slice(run.values);},

run_blot_reuse_principal_interface__Binding run=>{pool_blot_reuse_principal_interface__Binding.free_slice(run.values);},

run_blot_reuse_principal_interface__Nominal run=>{pool_blot_reuse_principal_interface__Nominal.free_slice(run.values);},

run_blot_reuse_principal_interface__Constructor run=>{pool_blot_reuse_principal_interface__Constructor.free_slice(run.values);},

run_blot_reuse_principal_interface__EffectFamily run=>{pool_blot_reuse_principal_interface__EffectFamily.free_slice(run.values);},

run_blot_reuse_principal_interface__EffectTemplate run=>{pool_blot_reuse_principal_interface__EffectTemplate.free_slice(run.values);},

run_blot_reuse_principal_interface__Associated run=>{pool_blot_reuse_principal_interface__Associated.free_slice(run.values);},

run_blot_reuse_principal_interface__Contract run=>{pool_blot_reuse_principal_interface__Contract.free_slice(run.values);},

run_blot_reuse_frozen_dependency__ImportResolution run=>{pool_blot_reuse_frozen_dependency__ImportResolution.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Export run=>{pool_blot_reuse_frozen_dependency__Export.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Fixity run=>{pool_blot_reuse_frozen_dependency__Fixity.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Symbol run=>{pool_blot_reuse_frozen_dependency__Symbol.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Module run=>{pool_blot_reuse_frozen_dependency__Module.free_slice(run.values);},

}links.free(at);}leases[owner].live=false;self_=Owner {..};leases.free(owner);}
fn deinit<T>(self_:Owned<T>&) {self_.owner.deinit();self_.value=default<T>();}
fn adopt(self_:Owner&,source:Owner&)->Error {
 assert(valid(self_)&&valid(source));if !unique(self_)||!unique(source) {return blot_error::Error.invalid_artifact;}if self_.lease==source.lease {return blot_error::Error.invalid_artifact;}
 let at=source.lease-1;let head=leases[at].head;if head!=0 {var tail=head;while links[tail-1].next!=0 {tail=links[tail-1].next;}links[tail-1].next=leases[self_.lease-1].head;leases[self_.lease-1].head=head;}
 leases[at].live=false;source=Owner {..};leases.free(at);return blot_error::Error.none;
}
fn alloc<T>(self_:Owner&,length:i64)->T[:],Error {return allocate(self_,default<T>(),length);}
fn copy<T>(self_:Owner&,values:const T[:])->T[:],Error {let result,error=blot_reuse_dependency_payload::alloc<T>(self_,values.len);if error!=blot_error::Error.none {return default<T[:]>(),error;}for value,index in values {result[index]=value;}return result,blot_error::Error.none;}

fn allocate(self_:Owner&,sample:u32,length:i64)->u32[:],Error {
 assert(unique(self_));if length<0 {return default<u32[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<u32[:]>(),blot_error::Error.none;}
 let run=pool_u32.alloc_slice(length);let error=remember(self_,Run.run_u32 {run, ..});if error!=blot_error::Error.none {pool_u32.free_slice(run);return default<u32[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const u32[:])->u32[:] {
 assert(unique(self_));if values.len==0 {return default<u32[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_u32 run=>{if blot_support::same_slice_identity(run.values,values) {return pool_u32.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const u32[:])->u32[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<u32>(self_,values.len);if error!=blot_error::Error.none {return default<u32[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<u32[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_numeric_proof_terms::Kind,length:i64)->blot_check_numeric_proof_terms::Kind[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_numeric_proof_terms::Kind[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_numeric_proof_terms::Kind[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_numeric_proof_terms__Kind.alloc_slice(length);let error=remember(self_,Run.run_blot_check_numeric_proof_terms__Kind {run, ..});if error!=blot_error::Error.none {pool_blot_check_numeric_proof_terms__Kind.free_slice(run);return default<blot_check_numeric_proof_terms::Kind[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_numeric_proof_terms::Kind[:])->blot_check_numeric_proof_terms::Kind[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_numeric_proof_terms::Kind[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_terms__Kind run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_terms__Kind.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_numeric_proof_terms::Kind[:])->blot_check_numeric_proof_terms::Kind[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_numeric_proof_terms::Kind>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_terms::Kind[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_terms::Kind[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_numeric_proof_terms::Term,length:i64)->blot_check_numeric_proof_terms::Term[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_numeric_proof_terms::Term[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_numeric_proof_terms::Term[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_numeric_proof_terms__Term.alloc_slice(length);let error=remember(self_,Run.run_blot_check_numeric_proof_terms__Term {run, ..});if error!=blot_error::Error.none {pool_blot_check_numeric_proof_terms__Term.free_slice(run);return default<blot_check_numeric_proof_terms::Term[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_numeric_proof_terms::Term[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_terms__Term run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_terms__Term.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_numeric_proof_terms::Term>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_terms::Term[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_terms::Term[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_numeric_proof_contracts::Requirement,length:i64)->blot_check_numeric_proof_contracts::Requirement[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_numeric_proof_contracts::Requirement[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_numeric_proof_contracts::Requirement[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_numeric_proof_contracts__Requirement.alloc_slice(length);let error=remember(self_,Run.run_blot_check_numeric_proof_contracts__Requirement {run, ..});if error!=blot_error::Error.none {pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run);return default<blot_check_numeric_proof_contracts::Requirement[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_numeric_proof_contracts::Requirement[:])->blot_check_numeric_proof_contracts::Requirement[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_numeric_proof_contracts::Requirement[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_contracts__Requirement run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_contracts__Requirement.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_numeric_proof_contracts::Requirement[:])->blot_check_numeric_proof_contracts::Requirement[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_numeric_proof_contracts::Requirement>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_contracts::Requirement[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_contracts::Requirement[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_numeric_proof_headers::Named,length:i64)->blot_check_numeric_proof_headers::Named[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_numeric_proof_headers::Named[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_numeric_proof_headers::Named[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_numeric_proof_headers__Named.alloc_slice(length);let error=remember(self_,Run.run_blot_check_numeric_proof_headers__Named {run, ..});if error!=blot_error::Error.none {pool_blot_check_numeric_proof_headers__Named.free_slice(run);return default<blot_check_numeric_proof_headers::Named[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_numeric_proof_headers::Named[:])->blot_check_numeric_proof_headers::Named[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_numeric_proof_headers::Named[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_headers__Named run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_headers__Named.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_numeric_proof_headers::Named[:])->blot_check_numeric_proof_headers::Named[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_numeric_proof_headers::Named>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_headers::Named[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_numeric_proof_headers::Named[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_capability_contracts::Term,length:i64)->blot_check_capability_contracts::Term[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_capability_contracts::Term[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_capability_contracts::Term[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_capability_contracts__Term.alloc_slice(length);let error=remember(self_,Run.run_blot_check_capability_contracts__Term {run, ..});if error!=blot_error::Error.none {pool_blot_check_capability_contracts__Term.free_slice(run);return default<blot_check_capability_contracts::Term[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_capability_contracts::Term[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_capability_contracts__Term run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_capability_contracts__Term.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_capability_contracts::Term>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_capability_contracts::Term[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_capability_contracts::Term[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_capability_contracts::Binding,length:i64)->blot_check_capability_contracts::Binding[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_capability_contracts::Binding[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_capability_contracts::Binding[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_capability_contracts__Binding.alloc_slice(length);let error=remember(self_,Run.run_blot_check_capability_contracts__Binding {run, ..});if error!=blot_error::Error.none {pool_blot_check_capability_contracts__Binding.free_slice(run);return default<blot_check_capability_contracts::Binding[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_capability_contracts::Binding[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_capability_contracts__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_capability_contracts__Binding.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_capability_contracts::Binding>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_capability_contracts::Binding[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_capability_contracts::Binding[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::FieldName,length:i64)->blot_check_core::FieldName[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::FieldName[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::FieldName[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__FieldName.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__FieldName {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__FieldName.free_slice(run);return default<blot_check_core::FieldName[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::FieldName[:])->blot_check_core::FieldName[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::FieldName[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__FieldName run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__FieldName.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::FieldName[:])->blot_check_core::FieldName[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::FieldName>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::FieldName[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::FieldName[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::RuntimeName,length:i64)->blot_check_core::RuntimeName[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::RuntimeName[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::RuntimeName[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__RuntimeName.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__RuntimeName {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__RuntimeName.free_slice(run);return default<blot_check_core::RuntimeName[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::RuntimeName[:])->blot_check_core::RuntimeName[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::RuntimeName[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RuntimeName run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__RuntimeName.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::RuntimeName[:])->blot_check_core::RuntimeName[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::RuntimeName>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::RuntimeName[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::RuntimeName[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::DeclarationDependencies,length:i64)->blot_check_core::DeclarationDependencies[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::DeclarationDependencies[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::DeclarationDependencies[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__DeclarationDependencies.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__DeclarationDependencies {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__DeclarationDependencies.free_slice(run);return default<blot_check_core::DeclarationDependencies[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::DeclarationDependencies[:])->blot_check_core::DeclarationDependencies[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::DeclarationDependencies[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DeclarationDependencies run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DeclarationDependencies.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::DeclarationDependencies[:])->blot_check_core::DeclarationDependencies[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::DeclarationDependencies>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::DeclarationDependencies[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::DeclarationDependencies[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::BindingRef,length:i64)->blot_check_core::BindingRef[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::BindingRef[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::BindingRef[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__BindingRef.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__BindingRef {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__BindingRef.free_slice(run);return default<blot_check_core::BindingRef[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::BindingRef[:])->blot_check_core::BindingRef[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::BindingRef[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__BindingRef run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__BindingRef.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::BindingRef[:])->blot_check_core::BindingRef[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::BindingRef>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::BindingRef[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::BindingRef[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::DependencyMember,length:i64)->blot_check_core::DependencyMember[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::DependencyMember[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::DependencyMember[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__DependencyMember.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__DependencyMember {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__DependencyMember.free_slice(run);return default<blot_check_core::DependencyMember[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::DependencyMember[:])->blot_check_core::DependencyMember[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::DependencyMember[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DependencyMember run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DependencyMember.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::DependencyMember[:])->blot_check_core::DependencyMember[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::DependencyMember>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::DependencyMember[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::DependencyMember[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::ErasedDeclarationReference,length:i64)->blot_check_core::ErasedDeclarationReference[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::ErasedDeclarationReference[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::ErasedDeclarationReference[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__ErasedDeclarationReference.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__ErasedDeclarationReference {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__ErasedDeclarationReference.free_slice(run);return default<blot_check_core::ErasedDeclarationReference[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::ErasedDeclarationReference[:])->blot_check_core::ErasedDeclarationReference[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::ErasedDeclarationReference[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ErasedDeclarationReference run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ErasedDeclarationReference.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::ErasedDeclarationReference[:])->blot_check_core::ErasedDeclarationReference[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::ErasedDeclarationReference>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::ErasedDeclarationReference[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::ErasedDeclarationReference[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::RequestLoopInfo,length:i64)->blot_check_core::RequestLoopInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::RequestLoopInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::RequestLoopInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__RequestLoopInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__RequestLoopInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__RequestLoopInfo.free_slice(run);return default<blot_check_core::RequestLoopInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::RequestLoopInfo[:])->blot_check_core::RequestLoopInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::RequestLoopInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RequestLoopInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__RequestLoopInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::RequestLoopInfo[:])->blot_check_core::RequestLoopInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::RequestLoopInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::RequestLoopInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::RequestLoopInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::RequestArm,length:i64)->blot_check_core::RequestArm[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::RequestArm[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::RequestArm[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__RequestArm.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__RequestArm {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__RequestArm.free_slice(run);return default<blot_check_core::RequestArm[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::RequestArm[:])->blot_check_core::RequestArm[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::RequestArm[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RequestArm run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__RequestArm.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::RequestArm[:])->blot_check_core::RequestArm[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::RequestArm>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::RequestArm[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::RequestArm[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_types::Node,length:i64)->blot_check_types::Node[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_types::Node[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_types::Node[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_types__Node.alloc_slice(length);let error=remember(self_,Run.run_blot_check_types__Node {run, ..});if error!=blot_error::Error.none {pool_blot_check_types__Node.free_slice(run);return default<blot_check_types::Node[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_types::Node[:])->blot_check_types::Node[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_types::Node[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Node run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__Node.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_types::Node[:])->blot_check_types::Node[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_types::Node>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_types::Node[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_types::Node[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_effects::Row,length:i64)->blot_check_effects::Row[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_effects::Row[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_effects::Row[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_effects__Row.alloc_slice(length);let error=remember(self_,Run.run_blot_check_effects__Row {run, ..});if error!=blot_error::Error.none {pool_blot_check_effects__Row.free_slice(run);return default<blot_check_effects::Row[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_effects::Row[:])->blot_check_effects::Row[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_effects::Row[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_effects__Row run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_effects__Row.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_effects::Row[:])->blot_check_effects::Row[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_effects::Row>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_effects::Row[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_effects::Row[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_types::Operation,length:i64)->blot_check_types::Operation[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_types::Operation[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_types::Operation[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_types__Operation.alloc_slice(length);let error=remember(self_,Run.run_blot_check_types__Operation {run, ..});if error!=blot_error::Error.none {pool_blot_check_types__Operation.free_slice(run);return default<blot_check_types::Operation[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_types::Operation[:])->blot_check_types::Operation[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_types::Operation[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Operation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__Operation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_types::Operation[:])->blot_check_types::Operation[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_types::Operation>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_types::Operation[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_types::Operation[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_types::QuantifierGoals,length:i64)->blot_check_types::QuantifierGoals[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_types::QuantifierGoals[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_types::QuantifierGoals[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_types__QuantifierGoals.alloc_slice(length);let error=remember(self_,Run.run_blot_check_types__QuantifierGoals {run, ..});if error!=blot_error::Error.none {pool_blot_check_types__QuantifierGoals.free_slice(run);return default<blot_check_types::QuantifierGoals[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_types::QuantifierGoals[:])->blot_check_types::QuantifierGoals[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_types::QuantifierGoals[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__QuantifierGoals run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__QuantifierGoals.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_types::QuantifierGoals[:])->blot_check_types::QuantifierGoals[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_types::QuantifierGoals>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_types::QuantifierGoals[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_types::QuantifierGoals[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_types::Obligation,length:i64)->blot_check_types::Obligation[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_types::Obligation[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_types::Obligation[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_types__Obligation.alloc_slice(length);let error=remember(self_,Run.run_blot_check_types__Obligation {run, ..});if error!=blot_error::Error.none {pool_blot_check_types__Obligation.free_slice(run);return default<blot_check_types::Obligation[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_types::Obligation[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Obligation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__Obligation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_types::Obligation>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_types::Obligation[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_types::Obligation[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Node,length:i64)->blot_check_core::Node[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Node[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Node[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Node.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Node {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Node.free_slice(run);return default<blot_check_core::Node[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Node[:])->blot_check_core::Node[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Node[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Node run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Node.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Node[:])->blot_check_core::Node[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Node>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Node[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Node[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_parse_ast::Span,length:i64)->blot_parse_ast::Span[:],Error {
 assert(unique(self_));if length<0 {return default<blot_parse_ast::Span[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_parse_ast::Span[:]>(),blot_error::Error.none;}
 let run=pool_blot_parse_ast__Span.alloc_slice(length);let error=remember(self_,Run.run_blot_parse_ast__Span {run, ..});if error!=blot_error::Error.none {pool_blot_parse_ast__Span.free_slice(run);return default<blot_parse_ast::Span[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_parse_ast::Span[:])->blot_parse_ast::Span[:] {
 assert(unique(self_));if values.len==0 {return default<blot_parse_ast::Span[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_parse_ast__Span run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_parse_ast__Span.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_parse_ast::Span[:])->blot_parse_ast::Span[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_parse_ast::Span>(self_,values.len);if error!=blot_error::Error.none {return default<blot_parse_ast::Span[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_parse_ast::Span[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Binding,length:i64)->blot_check_core::Binding[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Binding[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Binding[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Binding.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Binding {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Binding.free_slice(run);return default<blot_check_core::Binding[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Binding[:])->blot_check_core::Binding[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Binding[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Binding.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Binding[:])->blot_check_core::Binding[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Binding>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Binding[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Binding[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Body,length:i64)->blot_check_core::Body[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Body[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Body[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Body.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Body {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Body.free_slice(run);return default<blot_check_core::Body[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Body[:])->blot_check_core::Body[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Body[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Body run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Body.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Body[:])->blot_check_core::Body[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Body>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Body[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Body[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Parameter,length:i64)->blot_check_core::Parameter[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Parameter[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Parameter[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Parameter.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Parameter {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Parameter.free_slice(run);return default<blot_check_core::Parameter[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Parameter[:])->blot_check_core::Parameter[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Parameter[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Parameter run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Parameter.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Parameter[:])->blot_check_core::Parameter[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Parameter>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Parameter[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Parameter[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::CallInfo,length:i64)->blot_check_core::CallInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::CallInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::CallInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__CallInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__CallInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__CallInfo.free_slice(run);return default<blot_check_core::CallInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::CallInfo[:])->blot_check_core::CallInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::CallInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__CallInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__CallInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::CallInfo[:])->blot_check_core::CallInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::CallInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::CallInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::CallInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Merge,length:i64)->blot_check_core::Merge[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Merge[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Merge[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Merge.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Merge {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Merge.free_slice(run);return default<blot_check_core::Merge[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Merge[:])->blot_check_core::Merge[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Merge[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Merge run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Merge.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Merge[:])->blot_check_core::Merge[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Merge>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Merge[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Merge[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::List,length:i64)->blot_check_core::List[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::List[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::List[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__List.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__List {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__List.free_slice(run);return default<blot_check_core::List[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::List[:])->blot_check_core::List[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::List[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__List run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__List.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::List[:])->blot_check_core::List[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::List>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::List[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::List[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:u8,length:i64)->u8[:],Error {
 assert(unique(self_));if length<0 {return default<u8[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<u8[:]>(),blot_error::Error.none;}
 let run=pool_u8.alloc_slice(length);let error=remember(self_,Run.run_u8 {run, ..});if error!=blot_error::Error.none {pool_u8.free_slice(run);return default<u8[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const u8[:])->u8[:] {
 assert(unique(self_));if values.len==0 {return default<u8[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_u8 run=>{if blot_support::same_slice_identity(run.values,values) {return pool_u8.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const u8[:])->u8[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<u8>(self_,values.len);if error!=blot_error::Error.none {return default<u8[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<u8[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Obligation,length:i64)->blot_check_core::Obligation[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Obligation[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Obligation[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Obligation.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Obligation {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Obligation.free_slice(run);return default<blot_check_core::Obligation[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Obligation[:])->blot_check_core::Obligation[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Obligation[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Obligation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Obligation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Obligation[:])->blot_check_core::Obligation[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Obligation>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Obligation[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Obligation[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Nominal,length:i64)->blot_check_core::Nominal[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Nominal[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Nominal[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Nominal.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Nominal {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Nominal.free_slice(run);return default<blot_check_core::Nominal[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Nominal[:])->blot_check_core::Nominal[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Nominal[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Nominal run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Nominal.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Nominal[:])->blot_check_core::Nominal[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Nominal>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Nominal[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Nominal[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::OperationName,length:i64)->blot_check_core::OperationName[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::OperationName[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::OperationName[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__OperationName.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__OperationName {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__OperationName.free_slice(run);return default<blot_check_core::OperationName[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::OperationName[:])->blot_check_core::OperationName[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::OperationName[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__OperationName run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__OperationName.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::OperationName[:])->blot_check_core::OperationName[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::OperationName>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::OperationName[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::OperationName[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Constructor,length:i64)->blot_check_core::Constructor[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Constructor[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Constructor[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Constructor.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Constructor {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Constructor.free_slice(run);return default<blot_check_core::Constructor[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Constructor[:])->blot_check_core::Constructor[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Constructor[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Constructor run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Constructor.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Constructor[:])->blot_check_core::Constructor[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Constructor>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Constructor[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Constructor[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Projection,length:i64)->blot_check_core::Projection[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Projection[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Projection[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Projection.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Projection {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Projection.free_slice(run);return default<blot_check_core::Projection[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Projection[:])->blot_check_core::Projection[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Projection[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Projection run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Projection.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Projection[:])->blot_check_core::Projection[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Projection>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Projection[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Projection[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::ProjectionVariant,length:i64)->blot_check_core::ProjectionVariant[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::ProjectionVariant[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::ProjectionVariant[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__ProjectionVariant.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__ProjectionVariant {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__ProjectionVariant.free_slice(run);return default<blot_check_core::ProjectionVariant[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::ProjectionVariant[:])->blot_check_core::ProjectionVariant[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::ProjectionVariant[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ProjectionVariant run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ProjectionVariant.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::ProjectionVariant[:])->blot_check_core::ProjectionVariant[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::ProjectionVariant>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::ProjectionVariant[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::ProjectionVariant[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Pattern,length:i64)->blot_check_core::Pattern[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Pattern[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Pattern[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Pattern.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Pattern {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Pattern.free_slice(run);return default<blot_check_core::Pattern[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Pattern[:])->blot_check_core::Pattern[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Pattern[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Pattern run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Pattern.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Pattern[:])->blot_check_core::Pattern[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Pattern>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Pattern[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Pattern[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::PatternRow,length:i64)->blot_check_core::PatternRow[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::PatternRow[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::PatternRow[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__PatternRow.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__PatternRow {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__PatternRow.free_slice(run);return default<blot_check_core::PatternRow[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::PatternRow[:])->blot_check_core::PatternRow[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::PatternRow[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__PatternRow run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__PatternRow.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::PatternRow[:])->blot_check_core::PatternRow[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::PatternRow>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::PatternRow[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::PatternRow[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::MatchArm,length:i64)->blot_check_core::MatchArm[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::MatchArm[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::MatchArm[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__MatchArm.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__MatchArm {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__MatchArm.free_slice(run);return default<blot_check_core::MatchArm[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::MatchArm[:])->blot_check_core::MatchArm[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::MatchArm[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__MatchArm run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__MatchArm.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::MatchArm[:])->blot_check_core::MatchArm[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::MatchArm>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::MatchArm[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::MatchArm[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::MatchInfo,length:i64)->blot_check_core::MatchInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::MatchInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::MatchInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__MatchInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__MatchInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__MatchInfo.free_slice(run);return default<blot_check_core::MatchInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::MatchInfo[:])->blot_check_core::MatchInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::MatchInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__MatchInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__MatchInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::MatchInfo[:])->blot_check_core::MatchInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::MatchInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::MatchInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::MatchInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::UpdateInfo,length:i64)->blot_check_core::UpdateInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::UpdateInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::UpdateInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__UpdateInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__UpdateInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__UpdateInfo.free_slice(run);return default<blot_check_core::UpdateInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::UpdateInfo[:])->blot_check_core::UpdateInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::UpdateInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__UpdateInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__UpdateInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::UpdateInfo[:])->blot_check_core::UpdateInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::UpdateInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::UpdateInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::UpdateInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::UpdateStep,length:i64)->blot_check_core::UpdateStep[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::UpdateStep[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::UpdateStep[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__UpdateStep.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__UpdateStep {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__UpdateStep.free_slice(run);return default<blot_check_core::UpdateStep[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::UpdateStep[:])->blot_check_core::UpdateStep[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::UpdateStep[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__UpdateStep run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__UpdateStep.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::UpdateStep[:])->blot_check_core::UpdateStep[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::UpdateStep>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::UpdateStep[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::UpdateStep[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::ClosureInfo,length:i64)->blot_check_core::ClosureInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::ClosureInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::ClosureInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__ClosureInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__ClosureInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__ClosureInfo.free_slice(run);return default<blot_check_core::ClosureInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::ClosureInfo[:])->blot_check_core::ClosureInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::ClosureInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ClosureInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ClosureInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::ClosureInfo[:])->blot_check_core::ClosureInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::ClosureInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::ClosureInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::ClosureInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Associated,length:i64)->blot_check_core::Associated[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Associated[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Associated[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Associated.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Associated {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Associated.free_slice(run);return default<blot_check_core::Associated[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Associated[:])->blot_check_core::Associated[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Associated[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Associated run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Associated.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Associated[:])->blot_check_core::Associated[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Associated>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Associated[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Associated[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Contract,length:i64)->blot_check_core::Contract[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Contract[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Contract[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Contract.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Contract {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Contract.free_slice(run);return default<blot_check_core::Contract[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Contract[:])->blot_check_core::Contract[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Contract[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Contract run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Contract.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Contract[:])->blot_check_core::Contract[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Contract>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Contract[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Contract[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::ContractMember,length:i64)->blot_reuse_principal_interface::ContractMember[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::ContractMember[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::ContractMember[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__ContractMember.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__ContractMember {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__ContractMember.free_slice(run);return default<blot_reuse_principal_interface::ContractMember[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::ContractMember[:])->blot_reuse_principal_interface::ContractMember[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::ContractMember[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__ContractMember run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__ContractMember.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::ContractMember[:])->blot_reuse_principal_interface::ContractMember[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::ContractMember>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::ContractMember[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::ContractMember[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::Implementation,length:i64)->blot_reuse_principal_interface::Implementation[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::Implementation[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::Implementation[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__Implementation.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__Implementation {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__Implementation.free_slice(run);return default<blot_reuse_principal_interface::Implementation[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::Implementation[:])->blot_reuse_principal_interface::Implementation[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::Implementation[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Implementation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Implementation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::Implementation[:])->blot_reuse_principal_interface::Implementation[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Implementation>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Implementation[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Implementation[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::ImplementationMember,length:i64)->blot_reuse_principal_interface::ImplementationMember[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::ImplementationMember[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::ImplementationMember[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__ImplementationMember.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__ImplementationMember {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run);return default<blot_reuse_principal_interface::ImplementationMember[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::ImplementationMember[:])->blot_reuse_principal_interface::ImplementationMember[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::ImplementationMember[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__ImplementationMember run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__ImplementationMember.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::ImplementationMember[:])->blot_reuse_principal_interface::ImplementationMember[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::ImplementationMember>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::ImplementationMember[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::ImplementationMember[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::MemberTemplate,length:i64)->blot_reuse_principal_interface::MemberTemplate[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::MemberTemplate[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::MemberTemplate[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__MemberTemplate.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__MemberTemplate {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run);return default<blot_reuse_principal_interface::MemberTemplate[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::MemberTemplate[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__MemberTemplate run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__MemberTemplate.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::MemberTemplate>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::MemberTemplate[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::MemberTemplate[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::SelectedProof,length:i64)->blot_reuse_principal_interface::SelectedProof[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::SelectedProof[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::SelectedProof[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__SelectedProof.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__SelectedProof {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__SelectedProof.free_slice(run);return default<blot_reuse_principal_interface::SelectedProof[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::SelectedProof[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__SelectedProof run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__SelectedProof.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::SelectedProof>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::SelectedProof[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::SelectedProof[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::SelectedUse,length:i64)->blot_check_core::SelectedUse[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::SelectedUse[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::SelectedUse[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__SelectedUse.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__SelectedUse {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__SelectedUse.free_slice(run);return default<blot_check_core::SelectedUse[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::SelectedUse[:])->blot_check_core::SelectedUse[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::SelectedUse[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__SelectedUse run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__SelectedUse.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::SelectedUse[:])->blot_check_core::SelectedUse[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::SelectedUse>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::SelectedUse[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::SelectedUse[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::DictionarySelection,length:i64)->blot_check_core::DictionarySelection[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::DictionarySelection[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::DictionarySelection[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__DictionarySelection.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__DictionarySelection {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__DictionarySelection.free_slice(run);return default<blot_check_core::DictionarySelection[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::DictionarySelection[:])->blot_check_core::DictionarySelection[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::DictionarySelection[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DictionarySelection run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DictionarySelection.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::DictionarySelection[:])->blot_check_core::DictionarySelection[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::DictionarySelection>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::DictionarySelection[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::DictionarySelection[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::DictionaryUse,length:i64)->blot_check_core::DictionaryUse[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::DictionaryUse[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::DictionaryUse[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__DictionaryUse.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__DictionaryUse {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__DictionaryUse.free_slice(run);return default<blot_check_core::DictionaryUse[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::DictionaryUse[:])->blot_check_core::DictionaryUse[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::DictionaryUse[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DictionaryUse run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DictionaryUse.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::DictionaryUse[:])->blot_check_core::DictionaryUse[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::DictionaryUse>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::DictionaryUse[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::DictionaryUse[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Primitive,length:i64)->blot_check_core::Primitive[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Primitive[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Primitive[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Primitive.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Primitive {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Primitive.free_slice(run);return default<blot_check_core::Primitive[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Primitive[:])->blot_check_core::Primitive[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Primitive[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Primitive run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Primitive.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Primitive[:])->blot_check_core::Primitive[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Primitive>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Primitive[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Primitive[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::LoopInfo,length:i64)->blot_check_core::LoopInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::LoopInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::LoopInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__LoopInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__LoopInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__LoopInfo.free_slice(run);return default<blot_check_core::LoopInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::LoopInfo[:])->blot_check_core::LoopInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::LoopInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__LoopInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__LoopInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::LoopInfo[:])->blot_check_core::LoopInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::LoopInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::LoopInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::LoopInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::LoopCarry,length:i64)->blot_check_core::LoopCarry[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::LoopCarry[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::LoopCarry[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__LoopCarry.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__LoopCarry {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__LoopCarry.free_slice(run);return default<blot_check_core::LoopCarry[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::LoopCarry[:])->blot_check_core::LoopCarry[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::LoopCarry[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__LoopCarry run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__LoopCarry.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::LoopCarry[:])->blot_check_core::LoopCarry[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::LoopCarry>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::LoopCarry[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::LoopCarry[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::ResolverInfo,length:i64)->blot_check_core::ResolverInfo[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::ResolverInfo[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::ResolverInfo[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__ResolverInfo.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__ResolverInfo {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__ResolverInfo.free_slice(run);return default<blot_check_core::ResolverInfo[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::ResolverInfo[:])->blot_check_core::ResolverInfo[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::ResolverInfo[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ResolverInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ResolverInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::ResolverInfo[:])->blot_check_core::ResolverInfo[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::ResolverInfo>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::ResolverInfo[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::ResolverInfo[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::OperationValue,length:i64)->blot_check_core::OperationValue[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::OperationValue[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::OperationValue[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__OperationValue.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__OperationValue {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__OperationValue.free_slice(run);return default<blot_check_core::OperationValue[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::OperationValue[:])->blot_check_core::OperationValue[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::OperationValue[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__OperationValue run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__OperationValue.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::OperationValue[:])->blot_check_core::OperationValue[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::OperationValue>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::OperationValue[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::OperationValue[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::HandleEffects,length:i64)->blot_check_core::HandleEffects[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::HandleEffects[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::HandleEffects[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__HandleEffects.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__HandleEffects {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__HandleEffects.free_slice(run);return default<blot_check_core::HandleEffects[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::HandleEffects[:])->blot_check_core::HandleEffects[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::HandleEffects[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__HandleEffects run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__HandleEffects.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::HandleEffects[:])->blot_check_core::HandleEffects[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::HandleEffects>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::HandleEffects[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::HandleEffects[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_core::Diagnostic,length:i64)->blot_check_core::Diagnostic[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_core::Diagnostic[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Diagnostic[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_core__Diagnostic.alloc_slice(length);let error=remember(self_,Run.run_blot_check_core__Diagnostic {run, ..});if error!=blot_error::Error.none {pool_blot_check_core__Diagnostic.free_slice(run);return default<blot_check_core::Diagnostic[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_core::Diagnostic[:])->blot_check_core::Diagnostic[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_core::Diagnostic[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Diagnostic run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Diagnostic.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_core::Diagnostic[:])->blot_check_core::Diagnostic[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_core::Diagnostic>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_core::Diagnostic[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_core::Diagnostic[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_check_parameter_patterns::Node,length:i64)->blot_check_parameter_patterns::Node[:],Error {
 assert(unique(self_));if length<0 {return default<blot_check_parameter_patterns::Node[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_parameter_patterns::Node[:]>(),blot_error::Error.none;}
 let run=pool_blot_check_parameter_patterns__Node.alloc_slice(length);let error=remember(self_,Run.run_blot_check_parameter_patterns__Node {run, ..});if error!=blot_error::Error.none {pool_blot_check_parameter_patterns__Node.free_slice(run);return default<blot_check_parameter_patterns::Node[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_check_parameter_patterns::Node[:])->blot_check_parameter_patterns::Node[:] {
 assert(unique(self_));if values.len==0 {return default<blot_check_parameter_patterns::Node[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_parameter_patterns__Node run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_parameter_patterns__Node.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_check_parameter_patterns::Node[:])->blot_check_parameter_patterns::Node[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_check_parameter_patterns::Node>(self_,values.len);if error!=blot_error::Error.none {return default<blot_check_parameter_patterns::Node[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_check_parameter_patterns::Node[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::Binding,length:i64)->blot_reuse_principal_interface::Binding[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::Binding[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::Binding[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__Binding.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__Binding {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__Binding.free_slice(run);return default<blot_reuse_principal_interface::Binding[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::Binding[:])->blot_reuse_principal_interface::Binding[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::Binding[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Binding.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::Binding[:])->blot_reuse_principal_interface::Binding[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Binding>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Binding[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Binding[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::Nominal,length:i64)->blot_reuse_principal_interface::Nominal[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::Nominal[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::Nominal[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__Nominal.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__Nominal {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__Nominal.free_slice(run);return default<blot_reuse_principal_interface::Nominal[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::Nominal[:])->blot_reuse_principal_interface::Nominal[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::Nominal[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Nominal run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Nominal.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::Nominal[:])->blot_reuse_principal_interface::Nominal[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Nominal>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Nominal[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Nominal[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::Constructor,length:i64)->blot_reuse_principal_interface::Constructor[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::Constructor[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::Constructor[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__Constructor.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__Constructor {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__Constructor.free_slice(run);return default<blot_reuse_principal_interface::Constructor[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::Constructor[:])->blot_reuse_principal_interface::Constructor[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::Constructor[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Constructor run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Constructor.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::Constructor[:])->blot_reuse_principal_interface::Constructor[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Constructor>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Constructor[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Constructor[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::EffectFamily,length:i64)->blot_reuse_principal_interface::EffectFamily[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::EffectFamily[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::EffectFamily[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__EffectFamily.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__EffectFamily {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__EffectFamily.free_slice(run);return default<blot_reuse_principal_interface::EffectFamily[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::EffectFamily[:])->blot_reuse_principal_interface::EffectFamily[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::EffectFamily[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__EffectFamily run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__EffectFamily.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::EffectFamily[:])->blot_reuse_principal_interface::EffectFamily[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::EffectFamily>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::EffectFamily[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::EffectFamily[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::EffectTemplate,length:i64)->blot_reuse_principal_interface::EffectTemplate[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::EffectTemplate[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::EffectTemplate[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__EffectTemplate.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__EffectTemplate {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__EffectTemplate.free_slice(run);return default<blot_reuse_principal_interface::EffectTemplate[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::EffectTemplate[:])->blot_reuse_principal_interface::EffectTemplate[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::EffectTemplate[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__EffectTemplate run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__EffectTemplate.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::EffectTemplate[:])->blot_reuse_principal_interface::EffectTemplate[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::EffectTemplate>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::EffectTemplate[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::EffectTemplate[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::Associated,length:i64)->blot_reuse_principal_interface::Associated[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::Associated[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::Associated[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__Associated.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__Associated {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__Associated.free_slice(run);return default<blot_reuse_principal_interface::Associated[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::Associated[:])->blot_reuse_principal_interface::Associated[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::Associated[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Associated run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Associated.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::Associated[:])->blot_reuse_principal_interface::Associated[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Associated>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Associated[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Associated[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_principal_interface::Contract,length:i64)->blot_reuse_principal_interface::Contract[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_principal_interface::Contract[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_principal_interface::Contract[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_principal_interface__Contract.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_principal_interface__Contract {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_principal_interface__Contract.free_slice(run);return default<blot_reuse_principal_interface::Contract[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_principal_interface::Contract[:])->blot_reuse_principal_interface::Contract[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_principal_interface::Contract[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Contract run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Contract.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_principal_interface::Contract[:])->blot_reuse_principal_interface::Contract[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_principal_interface::Contract>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Contract[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_principal_interface::Contract[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_frozen_dependency::ImportResolution,length:i64)->blot_reuse_frozen_dependency::ImportResolution[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_frozen_dependency::ImportResolution[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_frozen_dependency::ImportResolution[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_frozen_dependency__ImportResolution.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_frozen_dependency__ImportResolution {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_frozen_dependency__ImportResolution.free_slice(run);return default<blot_reuse_frozen_dependency::ImportResolution[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_frozen_dependency::ImportResolution[:])->blot_reuse_frozen_dependency::ImportResolution[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_frozen_dependency::ImportResolution[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__ImportResolution run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_frozen_dependency__ImportResolution.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_frozen_dependency::ImportResolution[:])->blot_reuse_frozen_dependency::ImportResolution[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::ImportResolution>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::ImportResolution[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::ImportResolution[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_frozen_dependency::Export,length:i64)->blot_reuse_frozen_dependency::Export[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_frozen_dependency::Export[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_frozen_dependency::Export[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Export.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_frozen_dependency__Export {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_frozen_dependency__Export.free_slice(run);return default<blot_reuse_frozen_dependency::Export[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_frozen_dependency::Export[:])->blot_reuse_frozen_dependency::Export[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_frozen_dependency::Export[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Export run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_frozen_dependency__Export.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_frozen_dependency::Export[:])->blot_reuse_frozen_dependency::Export[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Export>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Export[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Export[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_frozen_dependency::Fixity,length:i64)->blot_reuse_frozen_dependency::Fixity[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_frozen_dependency::Fixity[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_frozen_dependency::Fixity[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Fixity.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_frozen_dependency__Fixity {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_frozen_dependency__Fixity.free_slice(run);return default<blot_reuse_frozen_dependency::Fixity[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_frozen_dependency::Fixity[:])->blot_reuse_frozen_dependency::Fixity[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_frozen_dependency::Fixity[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Fixity run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_frozen_dependency__Fixity.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_frozen_dependency::Fixity[:])->blot_reuse_frozen_dependency::Fixity[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Fixity>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Fixity[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Fixity[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_frozen_dependency::Symbol,length:i64)->blot_reuse_frozen_dependency::Symbol[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_frozen_dependency::Symbol[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_frozen_dependency::Symbol[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Symbol.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_frozen_dependency__Symbol {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_frozen_dependency__Symbol.free_slice(run);return default<blot_reuse_frozen_dependency::Symbol[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_frozen_dependency::Symbol[:])->blot_reuse_frozen_dependency::Symbol[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_frozen_dependency::Symbol[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Symbol run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_frozen_dependency__Symbol.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_frozen_dependency::Symbol[:])->blot_reuse_frozen_dependency::Symbol[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Symbol[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Symbol[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn allocate(self_:Owner&,sample:blot_reuse_frozen_dependency::Module,length:i64)->blot_reuse_frozen_dependency::Module[:],Error {
 assert(unique(self_));if length<0 {return default<blot_reuse_frozen_dependency::Module[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_frozen_dependency::Module[:]>(),blot_error::Error.none;}
 let run=pool_blot_reuse_frozen_dependency__Module.alloc_slice(length);let error=remember(self_,Run.run_blot_reuse_frozen_dependency__Module {run, ..});if error!=blot_error::Error.none {pool_blot_reuse_frozen_dependency__Module.free_slice(run);return default<blot_reuse_frozen_dependency::Module[:]>(),error;}return run,blot_error::Error.none;
}
fn mutable(self_:const Owner&,values:const blot_reuse_frozen_dependency::Module[:])->blot_reuse_frozen_dependency::Module[:] {
 assert(unique(self_));if values.len==0 {return default<blot_reuse_frozen_dependency::Module[:]>();}var next=leases[self_.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Module run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_frozen_dependency__Module.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable payload view must name this private owner's exact live run");
}
fn cloneValue(self_:Owner&,values:const blot_reuse_frozen_dependency::Module[:])->blot_reuse_frozen_dependency::Module[:],Error {
 let result,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Module>(self_,values.len);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Module[:]>(),error;}
 for value,index in values {let copied,error=cloneValue(self_,value);if error!=blot_error::Error.none {return default<blot_reuse_frozen_dependency::Module[:]>(),error;}result[index]=copied;}return result,blot_error::Error.none;
}

fn cloneValue(self_:Owner&,value:bool)->bool,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:f32)->f32,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:f64)->f64,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:i16)->i16,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:i32)->i32,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:i64)->i64,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:i8)->i8,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:u16)->u16,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:u32)->u32,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:u64)->u64,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:u8)->u8,Error {return value,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:u8[32])->u8[32],Error {var result=default<u8[32]>();for item,index in value {let copied,error=cloneValue(self_,item);if error!=blot_error::Error.none {return result,error;}result[index]=copied;}return result,blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:blot_support::Option<blot_check_numeric_proof_terms::Proposition>)->blot_support::Option<blot_check_numeric_proof_terms::Proposition>,Error {if !value.present {return blot_support::none<blot_check_numeric_proof_terms::Proposition>(),blot_error::Error.none;}let copied,error=cloneValue(self_,value.value);if error!=blot_error::Error.none {return blot_support::none<blot_check_numeric_proof_terms::Proposition>(),error;}return blot_support::some(copied),blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:blot_support::Option<blot_parse_ast::Span>)->blot_support::Option<blot_parse_ast::Span>,Error {if !value.present {return blot_support::none<blot_parse_ast::Span>(),blot_error::Error.none;}let copied,error=cloneValue(self_,value.value);if error!=blot_error::Error.none {return blot_support::none<blot_parse_ast::Span>(),error;}return blot_support::some(copied),blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:blot_support::Option<blot_reuse_principal_interface::ExternalTarget>)->blot_support::Option<blot_reuse_principal_interface::ExternalTarget>,Error {if !value.present {return blot_support::none<blot_reuse_principal_interface::ExternalTarget>(),blot_error::Error.none;}let copied,error=cloneValue(self_,value.value);if error!=blot_error::Error.none {return blot_support::none<blot_reuse_principal_interface::ExternalTarget>(),error;}return blot_support::some(copied),blot_error::Error.none;}

fn cloneValue(self_:Owner&,value:blot_check_core::Module)->blot_check_core::Module,Error {

var result=default<blot_check_core::Module>();

{let copied,error=cloneValue(self_,value.has_rank_contracts);if error!=blot_error::Error.none {return result,error;}result.has_rank_contracts=copied;}

{let copied,error=cloneValue(self_,value.has_usage_contracts);if error!=blot_error::Error.none {return result,error;}result.has_usage_contracts=copied;}

{let copied,error=cloneValue(self_,value.has_numeric_proofs);if error!=blot_error::Error.none {return result,error;}result.has_numeric_proofs=copied;}

{let copied,error=cloneValue(self_,value.proof_contracts);if error!=blot_error::Error.none {return result,error;}result.proof_contracts=copied;}

{let copied,error=cloneValue(self_,value.capability_contracts);if error!=blot_error::Error.none {return result,error;}result.capability_contracts=copied;}

{let copied,error=cloneValue(self_,value.field_names);if error!=blot_error::Error.none {return result,error;}result.field_names=copied;}

{let copied,error=cloneValue(self_,value.runtime_names);if error!=blot_error::Error.none {return result,error;}result.runtime_names=copied;}

{let copied,error=cloneValue(self_,value.source_names);if error!=blot_error::Error.none {return result,error;}result.source_names=copied;}

{let copied,error=cloneValue(self_,value.declaration_dependencies);if error!=blot_error::Error.none {return result,error;}result.declaration_dependencies=copied;}

{let copied,error=cloneValue(self_,value.dependency_references);if error!=blot_error::Error.none {return result,error;}result.dependency_references=copied;}

{let copied,error=cloneValue(self_,value.dependency_members);if error!=blot_error::Error.none {return result,error;}result.dependency_members=copied;}

{let copied,error=cloneValue(self_,value.erased_declaration_references);if error!=blot_error::Error.none {return result,error;}result.erased_declaration_references=copied;}

{let copied,error=cloneValue(self_,value.request_loops);if error!=blot_error::Error.none {return result,error;}result.request_loops=copied;}

{let copied,error=cloneValue(self_,value.request_arms);if error!=blot_error::Error.none {return result,error;}result.request_arms=copied;}

{let copied,error=cloneValue(self_,value.tag_calls);if error!=blot_error::Error.none {return result,error;}result.tag_calls=copied;}

{let copied,error=cloneValue(self_,value.unit);if error!=blot_error::Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self_,value.types);if error!=blot_error::Error.none {return result,error;}result.types=copied;}

{let copied,error=cloneValue(self_,value.nodes);if error!=blot_error::Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self_,value.spans);if error!=blot_error::Error.none {return result,error;}result.spans=copied;}

{let copied,error=cloneValue(self_,value.extra);if error!=blot_error::Error.none {return result,error;}result.extra=copied;}

{let copied,error=cloneValue(self_,value.bindings);if error!=blot_error::Error.none {return result,error;}result.bindings=copied;}

{let copied,error=cloneValue(self_,value.bodies);if error!=blot_error::Error.none {return result,error;}result.bodies=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.references);if error!=blot_error::Error.none {return result,error;}result.references=copied;}

{let copied,error=cloneValue(self_,value.calls);if error!=blot_error::Error.none {return result,error;}result.calls=copied;}

{let copied,error=cloneValue(self_,value.merges);if error!=blot_error::Error.none {return result,error;}result.merges=copied;}

{let copied,error=cloneValue(self_,value.merge_ranges);if error!=blot_error::Error.none {return result,error;}result.merge_ranges=copied;}

{let copied,error=cloneValue(self_,value.names);if error!=blot_error::Error.none {return result,error;}result.names=copied;}

{let copied,error=cloneValue(self_,value.obligations);if error!=blot_error::Error.none {return result,error;}result.obligations=copied;}

{let copied,error=cloneValue(self_,value.nominals);if error!=blot_error::Error.none {return result,error;}result.nominals=copied;}

{let copied,error=cloneValue(self_,value.operation_names);if error!=blot_error::Error.none {return result,error;}result.operation_names=copied;}

{let copied,error=cloneValue(self_,value.constructors);if error!=blot_error::Error.none {return result,error;}result.constructors=copied;}

{let copied,error=cloneValue(self_,value.projections);if error!=blot_error::Error.none {return result,error;}result.projections=copied;}

{let copied,error=cloneValue(self_,value.projection_variants);if error!=blot_error::Error.none {return result,error;}result.projection_variants=copied;}

{let copied,error=cloneValue(self_,value.patterns);if error!=blot_error::Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self_,value.pattern_rows);if error!=blot_error::Error.none {return result,error;}result.pattern_rows=copied;}

{let copied,error=cloneValue(self_,value.match_arms);if error!=blot_error::Error.none {return result,error;}result.match_arms=copied;}

{let copied,error=cloneValue(self_,value.matches);if error!=blot_error::Error.none {return result,error;}result.matches=copied;}

{let copied,error=cloneValue(self_,value.updates);if error!=blot_error::Error.none {return result,error;}result.updates=copied;}

{let copied,error=cloneValue(self_,value.update_steps);if error!=blot_error::Error.none {return result,error;}result.update_steps=copied;}

{let copied,error=cloneValue(self_,value.closures);if error!=blot_error::Error.none {return result,error;}result.closures=copied;}

{let copied,error=cloneValue(self_,value.associated);if error!=blot_error::Error.none {return result,error;}result.associated=copied;}

{let copied,error=cloneValue(self_,value.contracts);if error!=blot_error::Error.none {return result,error;}result.contracts=copied;}

{let copied,error=cloneValue(self_,value.contract_members);if error!=blot_error::Error.none {return result,error;}result.contract_members=copied;}

{let copied,error=cloneValue(self_,value.implementations);if error!=blot_error::Error.none {return result,error;}result.implementations=copied;}

{let copied,error=cloneValue(self_,value.implementation_members);if error!=blot_error::Error.none {return result,error;}result.implementation_members=copied;}

{let copied,error=cloneValue(self_,value.member_templates);if error!=blot_error::Error.none {return result,error;}result.member_templates=copied;}

{let copied,error=cloneValue(self_,value.selected_proofs);if error!=blot_error::Error.none {return result,error;}result.selected_proofs=copied;}

{let copied,error=cloneValue(self_,value.selected_members);if error!=blot_error::Error.none {return result,error;}result.selected_members=copied;}

{let copied,error=cloneValue(self_,value.selected_edges);if error!=blot_error::Error.none {return result,error;}result.selected_edges=copied;}

{let copied,error=cloneValue(self_,value.selected_uses);if error!=blot_error::Error.none {return result,error;}result.selected_uses=copied;}

{let copied,error=cloneValue(self_,value.dictionary_selections);if error!=blot_error::Error.none {return result,error;}result.dictionary_selections=copied;}

{let copied,error=cloneValue(self_,value.dictionary_uses);if error!=blot_error::Error.none {return result,error;}result.dictionary_uses=copied;}

{let copied,error=cloneValue(self_,value.primitives);if error!=blot_error::Error.none {return result,error;}result.primitives=copied;}

{let copied,error=cloneValue(self_,value.loops);if error!=blot_error::Error.none {return result,error;}result.loops=copied;}

{let copied,error=cloneValue(self_,value.loop_carries);if error!=blot_error::Error.none {return result,error;}result.loop_carries=copied;}

{let copied,error=cloneValue(self_,value.resolver_ops);if error!=blot_error::Error.none {return result,error;}result.resolver_ops=copied;}

{let copied,error=cloneValue(self_,value.operation_values);if error!=blot_error::Error.none {return result,error;}result.operation_values=copied;}

{let copied,error=cloneValue(self_,value.handle_effects);if error!=blot_error::Error.none {return result,error;}result.handle_effects=copied;}

{let copied,error=cloneValue(self_,value.dispatch_signatures);if error!=blot_error::Error.none {return result,error;}result.dispatch_signatures=copied;}

{let copied,error=cloneValue(self_,value.diagnostics);if error!=blot_error::Error.none {return result,error;}result.diagnostics=copied;}

{let copied,error=cloneValue(self_,value.body_lowerings);if error!=blot_error::Error.none {return result,error;}result.body_lowerings=copied;}

result.owner_id=blot_native::fresh_owner_id();
var packages=false;for node in result.nodes {if node.tag==blot_check_core::Tag.package_pack {packages=true;break;}}
if packages {let run,error=blot_reuse_dependency_payload::alloc<u32>(self_,result.nodes.len);if error!=blot_error::Error.none {return result,error;}for node,index in result.nodes {run[index]=node.a;}result.package_payloads=run;}


return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_headers::Named)->blot_check_numeric_proof_headers::Named,Error {

var result=default<blot_check_numeric_proof_headers::Named>();

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.header);if error!=blot_error::Error.none {return result,error;}result.header=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_headers::Owned)->blot_check_numeric_proof_headers::Owned,Error {

var result=default<blot_check_numeric_proof_headers::Owned>();

{let copied,error=cloneValue(self_,value.arity);if error!=blot_error::Error.none {return result,error;}result.arity=copied;}

{let copied,error=cloneValue(self_,value.value_slots);if error!=blot_error::Error.none {return result,error;}result.value_slots=copied;}

{let copied,error=cloneValue(self_,value.proof_slots);if error!=blot_error::Error.none {return result,error;}result.proof_slots=copied;}

{let copied,error=cloneValue(self_,value.values);if error!=blot_error::Error.none {return result,error;}result.values=copied;}

{let copied,error=cloneValue(self_,value.operands);if error!=blot_error::Error.none {return result,error;}result.operands=copied;}

{let copied,error=cloneValue(self_,value.requirements);if error!=blot_error::Error.none {return result,error;}result.requirements=copied;}

{let copied,error=cloneValue(self_,value.result);if error!=blot_error::Error.none {return result,error;}result.result=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_terms::Kind)->blot_check_numeric_proof_terms::Kind,Error {

match value {

unsigned32=>{
return blot_check_numeric_proof_terms::Kind.unsigned32,blot_error::Error.none;},

array=>{
return blot_check_numeric_proof_terms::Kind.array,blot_error::Error.none;},

list=>{
return blot_check_numeric_proof_terms::Kind.list,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_terms::Term)->blot_check_numeric_proof_terms::Term,Error {

var result=default<blot_check_numeric_proof_terms::Term>();

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.a);if error!=blot_error::Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self_,value.b);if error!=blot_error::Error.none {return result,error;}result.b=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_terms::Tag)->blot_check_numeric_proof_terms::Tag,Error {

match value {

literal=>{
return blot_check_numeric_proof_terms::Tag.literal,blot_error::Error.none;},

formal=>{
return blot_check_numeric_proof_terms::Tag.formal,blot_error::Error.none;},

capture=>{
return blot_check_numeric_proof_terms::Tag.capture,blot_error::Error.none;},

version=>{
return blot_check_numeric_proof_terms::Tag.version,blot_error::Error.none;},

length=>{
return blot_check_numeric_proof_terms::Tag.length,blot_error::Error.none;},

complement=>{
return blot_check_numeric_proof_terms::Tag.complement,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_contracts::Requirement)->blot_check_numeric_proof_contracts::Requirement,Error {

var result=default<blot_check_numeric_proof_contracts::Requirement>();

{let copied,error=cloneValue(self_,value.before);if error!=blot_error::Error.none {return result,error;}result.before=copied;}

{let copied,error=cloneValue(self_,value.proposition);if error!=blot_error::Error.none {return result,error;}result.proposition=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_terms::Proposition)->blot_check_numeric_proof_terms::Proposition,Error {

var result=default<blot_check_numeric_proof_terms::Proposition>();

{let copied,error=cloneValue(self_,value.relation);if error!=blot_error::Error.none {return result,error;}result.relation=copied;}

{let copied,error=cloneValue(self_,value.left);if error!=blot_error::Error.none {return result,error;}result.left=copied;}

{let copied,error=cloneValue(self_,value.right);if error!=blot_error::Error.none {return result,error;}result.right=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_numeric_proof_terms::Relation)->blot_check_numeric_proof_terms::Relation,Error {

match value {

eq=>{
return blot_check_numeric_proof_terms::Relation.eq,blot_error::Error.none;},

lt=>{
return blot_check_numeric_proof_terms::Relation.lt,blot_error::Error.none;},

le=>{
return blot_check_numeric_proof_terms::Relation.le,blot_error::Error.none;},

add_fits=>{
return blot_check_numeric_proof_terms::Relation.add_fits,blot_error::Error.none;},

sub_fits=>{
return blot_check_numeric_proof_terms::Relation.sub_fits,blot_error::Error.none;},

index=>{
return blot_check_numeric_proof_terms::Relation.index,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_capability_contracts::Collection)->blot_check_capability_contracts::Collection,Error {

var result=default<blot_check_capability_contracts::Collection>();

{let copied,error=cloneValue(self_,value.nodes);if error!=blot_error::Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self_,value.words);if error!=blot_error::Error.none {return result,error;}result.words=copied;}

{let copied,error=cloneValue(self_,value.bindings);if error!=blot_error::Error.none {return result,error;}result.bindings=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_capability_contracts::Term)->blot_check_capability_contracts::Term,Error {

var result=default<blot_check_capability_contracts::Term>();

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.a);if error!=blot_error::Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self_,value.b);if error!=blot_error::Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self_,value.c);if error!=blot_error::Error.none {return result,error;}result.c=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_capability_contracts::Tag)->blot_check_capability_contracts::Tag,Error {

match value {

empty=>{
return blot_check_capability_contracts::Tag.empty,blot_error::Error.none;},

unknown=>{
return blot_check_capability_contracts::Tag.unknown,blot_error::Error.none;},

parameter=>{
return blot_check_capability_contracts::Tag.parameter,blot_error::Error.none;},

authority=>{
return blot_check_capability_contracts::Tag.authority,blot_error::Error.none;},

captures=>{
return blot_check_capability_contracts::Tag.captures,blot_error::Error.none;},

product=>{
return blot_check_capability_contracts::Tag.product,blot_error::Error.none;},

record=>{
return blot_check_capability_contracts::Tag.record,blot_error::Error.none;},

wrapped=>{
return blot_check_capability_contracts::Tag.wrapped,blot_error::Error.none;},

join=>{
return blot_check_capability_contracts::Tag.join,blot_error::Error.none;},

project=>{
return blot_check_capability_contracts::Tag.project,blot_error::Error.none;},

elements=>{
return blot_check_capability_contracts::Tag.elements,blot_error::Error.none;},

argument=>{
return blot_check_capability_contracts::Tag.argument,blot_error::Error.none;},

callable=>{
return blot_check_capability_contracts::Tag.callable,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_capability_contracts::Binding)->blot_check_capability_contracts::Binding,Error {

var result=default<blot_check_capability_contracts::Binding>();

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.root);if error!=blot_error::Error.none {return result,error;}result.root=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::FieldName)->blot_check_core::FieldName,Error {

var result=default<blot_check_core::FieldName>();

{let copied,error=cloneValue(self_,value.symbol);if error!=blot_error::Error.none {return result,error;}result.symbol=copied;}

{let copied,error=cloneValue(self_,value.spelling);if error!=blot_error::Error.none {return result,error;}result.spelling=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Name)->blot_check_core::Name,Error {

var result=default<blot_check_core::Name>();

{let copied,error=cloneValue(self_,value.start);if error!=blot_error::Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self_,value.len);if error!=blot_error::Error.none {return result,error;}result.len=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::RuntimeName)->blot_check_core::RuntimeName,Error {

var result=default<blot_check_core::RuntimeName>();

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.point);if error!=blot_error::Error.none {return result,error;}result.point=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::DeclarationDependencies)->blot_check_core::DeclarationDependencies,Error {

var result=default<blot_check_core::DeclarationDependencies>();

{let copied,error=cloneValue(self_,value.references);if error!=blot_error::Error.none {return result,error;}result.references=copied;}

{let copied,error=cloneValue(self_,value.members);if error!=blot_error::Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self_,value.runtime_metadata);if error!=blot_error::Error.none {return result,error;}result.runtime_metadata=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::List)->blot_check_core::List,Error {

var result=default<blot_check_core::List>();

{let copied,error=cloneValue(self_,value.start);if error!=blot_error::Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self_,value.len);if error!=blot_error::Error.none {return result,error;}result.len=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::BindingRef)->blot_check_core::BindingRef,Error {

var result=default<blot_check_core::BindingRef>();

{let copied,error=cloneValue(self_,value.unit);if error!=blot_error::Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::DependencyMember)->blot_check_core::DependencyMember,Error {

var result=default<blot_check_core::DependencyMember>();

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.operator);if error!=blot_error::Error.none {return result,error;}result.operator=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::Operator)->blot_check_types::Operator,Error {

match value {

none=>{
return blot_check_types::Operator.none,blot_error::Error.none;},

add=>{
return blot_check_types::Operator.add,blot_error::Error.none;},

sub=>{
return blot_check_types::Operator.sub,blot_error::Error.none;},

mul=>{
return blot_check_types::Operator.mul,blot_error::Error.none;},

div=>{
return blot_check_types::Operator.div,blot_error::Error.none;},

rem=>{
return blot_check_types::Operator.rem,blot_error::Error.none;},

equal=>{
return blot_check_types::Operator.equal,blot_error::Error.none;},

not_equal=>{
return blot_check_types::Operator.not_equal,blot_error::Error.none;},

less=>{
return blot_check_types::Operator.less,blot_error::Error.none;},

less_equal=>{
return blot_check_types::Operator.less_equal,blot_error::Error.none;},

greater=>{
return blot_check_types::Operator.greater,blot_error::Error.none;},

greater_equal=>{
return blot_check_types::Operator.greater_equal,blot_error::Error.none;},

bit_and=>{
return blot_check_types::Operator.bit_and,blot_error::Error.none;},

bit_or=>{
return blot_check_types::Operator.bit_or,blot_error::Error.none;},

bit_xor=>{
return blot_check_types::Operator.bit_xor,blot_error::Error.none;},

shift_left=>{
return blot_check_types::Operator.shift_left,blot_error::Error.none;},

shift_right=>{
return blot_check_types::Operator.shift_right,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::ErasedDeclarationReference)->blot_check_core::ErasedDeclarationReference,Error {

var result=default<blot_check_core::ErasedDeclarationReference>();

{let copied,error=cloneValue(self_,value.node);if error!=blot_error::Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::RequestLoopInfo)->blot_check_core::RequestLoopInfo,Error {

var result=default<blot_check_core::RequestLoopInfo>();

{let copied,error=cloneValue(self_,value.computation);if error!=blot_error::Error.none {return result,error;}result.computation=copied;}

{let copied,error=cloneValue(self_,value.action_type);if error!=blot_error::Error.none {return result,error;}result.action_type=copied;}

{let copied,error=cloneValue(self_,value.value_type);if error!=blot_error::Error.none {return result,error;}result.value_type=copied;}

{let copied,error=cloneValue(self_,value.result_type);if error!=blot_error::Error.none {return result,error;}result.result_type=copied;}

{let copied,error=cloneValue(self_,value.state_type);if error!=blot_error::Error.none {return result,error;}result.state_type=copied;}

{let copied,error=cloneValue(self_,value.arms);if error!=blot_error::Error.none {return result,error;}result.arms=copied;}

{let copied,error=cloneValue(self_,value.completion_pattern);if error!=blot_error::Error.none {return result,error;}result.completion_pattern=copied;}

{let copied,error=cloneValue(self_,value.completion_body);if error!=blot_error::Error.none {return result,error;}result.completion_body=copied;}

{let copied,error=cloneValue(self_,value.completion_state_bindings);if error!=blot_error::Error.none {return result,error;}result.completion_state_bindings=copied;}

{let copied,error=cloneValue(self_,value.carries);if error!=blot_error::Error.none {return result,error;}result.carries=copied;}

{let copied,error=cloneValue(self_,value.return_target);if error!=blot_error::Error.none {return result,error;}result.return_target=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::RequestArm)->blot_check_core::RequestArm,Error {

var result=default<blot_check_core::RequestArm>();

{let copied,error=cloneValue(self_,value.operation);if error!=blot_error::Error.none {return result,error;}result.operation=copied;}

{let copied,error=cloneValue(self_,value.callback);if error!=blot_error::Error.none {return result,error;}result.callback=copied;}

{let copied,error=cloneValue(self_,value.selector);if error!=blot_error::Error.none {return result,error;}result.selector=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Types)->blot_check_core::Types,Error {

var result=default<blot_check_core::Types>();

{let copied,error=cloneValue(self_,value.nodes);if error!=blot_error::Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self_,value.extra);if error!=blot_error::Error.none {return result,error;}result.extra=copied;}

{let copied,error=cloneValue(self_,value.effects);if error!=blot_error::Error.none {return result,error;}result.effects=copied;}

{let copied,error=cloneValue(self_,value.operations);if error!=blot_error::Error.none {return result,error;}result.operations=copied;}

{let copied,error=cloneValue(self_,value.quantifier_goals);if error!=blot_error::Error.none {return result,error;}result.quantifier_goals=copied;}

{let copied,error=cloneValue(self_,value.quantifier_obligations);if error!=blot_error::Error.none {return result,error;}result.quantifier_obligations=copied;}

result.owner_id=blot_native::fresh_owner_id();

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::Node)->blot_check_types::Node,Error {

var result=default<blot_check_types::Node>();

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.closed_height);if error!=blot_error::Error.none {return result,error;}result.closed_height=copied;}

{let copied,error=cloneValue(self_,value.closed_generation);if error!=blot_error::Error.none {return result,error;}result.closed_generation=copied;}

{let copied,error=cloneValue(self_,value.a);if error!=blot_error::Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self_,value.b);if error!=blot_error::Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self_,value.c);if error!=blot_error::Error.none {return result,error;}result.c=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::Tag)->blot_check_types::Tag,Error {

match value {

absent=>{
return blot_check_types::Tag.absent,blot_error::Error.none;},

unit=>{
return blot_check_types::Tag.unit,blot_error::Error.none;},

boolean=>{
return blot_check_types::Tag.boolean,blot_error::Error.none;},

unsigned32=>{
return blot_check_types::Tag.unsigned32,blot_error::Error.none;},

floating32=>{
return blot_check_types::Tag.floating32,blot_error::Error.none;},

never=>{
return blot_check_types::Tag.never,blot_error::Error.none;},

variable=>{
return blot_check_types::Tag.variable,blot_error::Error.none;},

function=>{
return blot_check_types::Tag.function,blot_error::Error.none;},

product=>{
return blot_check_types::Tag.product,blot_error::Error.none;},

record=>{
return blot_check_types::Tag.record,blot_error::Error.none;},

nominal=>{
return blot_check_types::Tag.nominal,blot_error::Error.none;},

array=>{
return blot_check_types::Tag.array,blot_error::Error.none;},

list=>{
return blot_check_types::Tag.list,blot_error::Error.none;},

cursor=>{
return blot_check_types::Tag.cursor,blot_error::Error.none;},

type_constructor=>{
return blot_check_types::Tag.type_constructor,blot_error::Error.none;},

resolver=>{
return blot_check_types::Tag.resolver,blot_error::Error.none;},

provider=>{
return blot_check_types::Tag.provider,blot_error::Error.none;},

state_provider=>{
return blot_check_types::Tag.state_provider,blot_error::Error.none;},

projection=>{
return blot_check_types::Tag.projection,blot_error::Error.none;},

scoped=>{
return blot_check_types::Tag.scoped,blot_error::Error.none;},

instance_selection=>{
return blot_check_types::Tag.instance_selection,blot_error::Error.none;},

erased_proof=>{
return blot_check_types::Tag.erased_proof,blot_error::Error.none;},

forall=>{
return blot_check_types::Tag.forall,blot_error::Error.none;},

existential=>{
return blot_check_types::Tag.existential,blot_error::Error.none;},

bound=>{
return blot_check_types::Tag.bound,blot_error::Error.none;},

rigid=>{
return blot_check_types::Tag.rigid,blot_error::Error.none;},

usage=>{
return blot_check_types::Tag.usage,blot_error::Error.none;},

instance_version=>{
return blot_check_types::Tag.instance_version,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::EffectRows)->blot_check_core::EffectRows,Error {

var result=default<blot_check_core::EffectRows>();

{let copied,error=cloneValue(self_,value.rows);if error!=blot_error::Error.none {return result,error;}result.rows=copied;}

{let copied,error=cloneValue(self_,value.labels);if error!=blot_error::Error.none {return result,error;}result.labels=copied;}

{let copied,error=cloneValue(self_,value.variable_count);if error!=blot_error::Error.none {return result,error;}result.variable_count=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_effects::Row)->blot_check_effects::Row,Error {

var result=default<blot_check_effects::Row>();

{let copied,error=cloneValue(self_,value.labels);if error!=blot_error::Error.none {return result,error;}result.labels=copied;}

{let copied,error=cloneValue(self_,value.tail);if error!=blot_error::Error.none {return result,error;}result.tail=copied;}

{let copied,error=cloneValue(self_,value.cursor);if error!=blot_error::Error.none {return result,error;}result.cursor=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_effects::List)->blot_check_effects::List,Error {

var result=default<blot_check_effects::List>();

{let copied,error=cloneValue(self_,value.start);if error!=blot_error::Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self_,value.len);if error!=blot_error::Error.none {return result,error;}result.len=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_effects::Tail)->blot_check_effects::Tail,Error {

match value {

closed=>{
return blot_check_effects::Tail.closed,blot_error::Error.none;},

variable payload=>{
let value,error_value=cloneValue(self_,payload.value);if error_value!=blot_error::Error.none {return default<blot_check_effects::Tail>(),error_value;}
return blot_check_effects::Tail.variable {value:value, ..},blot_error::Error.none;},

parameter payload=>{
let value,error_value=cloneValue(self_,payload.value);if error_value!=blot_error::Error.none {return default<blot_check_effects::Tail>(),error_value;}
return blot_check_effects::Tail.parameter {value:value, ..},blot_error::Error.none;},

formal payload=>{
let value,error_value=cloneValue(self_,payload.value);if error_value!=blot_error::Error.none {return default<blot_check_effects::Tail>(),error_value;}
return blot_check_effects::Tail.formal {value:value, ..},blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_types::Operation)->blot_check_types::Operation,Error {

var result=default<blot_check_types::Operation>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.arguments);if error!=blot_error::Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self_,value.instance);if error!=blot_error::Error.none {return result,error;}result.instance=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::NominalIdentity)->blot_check_types::NominalIdentity,Error {

var result=default<blot_check_types::NominalIdentity>();

{let copied,error=cloneValue(self_,value.unit);if error!=blot_error::Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self_,value.decl);if error!=blot_error::Error.none {return result,error;}result.decl=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::List)->blot_check_types::List,Error {

var result=default<blot_check_types::List>();

{let copied,error=cloneValue(self_,value.start);if error!=blot_error::Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self_,value.len);if error!=blot_error::Error.none {return result,error;}result.len=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::QuantifierGoals)->blot_check_types::QuantifierGoals,Error {

var result=default<blot_check_types::QuantifierGoals>();

{let copied,error=cloneValue(self_,value.owner);if error!=blot_error::Error.none {return result,error;}result.owner=copied;}

{let copied,error=cloneValue(self_,value.goals);if error!=blot_error::Error.none {return result,error;}result.goals=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::Obligation)->blot_check_types::Obligation,Error {

var result=default<blot_check_types::Obligation>();

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.source);if error!=blot_error::Error.none {return result,error;}result.source=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.result);if error!=blot_error::Error.none {return result,error;}result.result=copied;}

{let copied,error=cloneValue(self_,value.other);if error!=blot_error::Error.none {return result,error;}result.other=copied;}

{let copied,error=cloneValue(self_,value.signature);if error!=blot_error::Error.none {return result,error;}result.signature=copied;}

{let copied,error=cloneValue(self_,value.operator);if error!=blot_error::Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.explicit);if error!=blot_error::Error.none {return result,error;}result.explicit=copied;}

{let copied,error=cloneValue(self_,value.qualification_span);if error!=blot_error::Error.none {return result,error;}result.qualification_span=copied;}

{let copied,error=cloneValue(self_,value.qualification_unit);if error!=blot_error::Error.none {return result,error;}result.qualification_unit=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_types::ObligationKind)->blot_check_types::ObligationKind,Error {

match value {

arithmetic=>{
return blot_check_types::ObligationKind.arithmetic,blot_error::Error.none;},

ordered=>{
return blot_check_types::ObligationKind.ordered,blot_error::Error.none;},

equality=>{
return blot_check_types::ObligationKind.equality,blot_error::Error.none;},

integer=>{
return blot_check_types::ObligationKind.integer,blot_error::Error.none;},

field=>{
return blot_check_types::ObligationKind.field,blot_error::Error.none;},

writable_field=>{
return blot_check_types::ObligationKind.writable_field,blot_error::Error.none;},

dispatch=>{
return blot_check_types::ObligationKind.dispatch,blot_error::Error.none;},

result_dispatch=>{
return blot_check_types::ObligationKind.result_dispatch,blot_error::Error.none;},

monad_factory=>{
return blot_check_types::ObligationKind.monad_factory,blot_error::Error.none;},

resolver_dispatch=>{
return blot_check_types::ObligationKind.resolver_dispatch,blot_error::Error.none;},

resolver_shape=>{
return blot_check_types::ObligationKind.resolver_shape,blot_error::Error.none;},

effect_operation=>{
return blot_check_types::ObligationKind.effect_operation,blot_error::Error.none;},

effect_handler=>{
return blot_check_types::ObligationKind.effect_handler,blot_error::Error.none;},

receiver=>{
return blot_check_types::ObligationKind.receiver,blot_error::Error.none;},

update=>{
return blot_check_types::ObligationKind.update,blot_error::Error.none;},

type_rep=>{
return blot_check_types::ObligationKind.type_rep,blot_error::Error.none;},

effect_rep=>{
return blot_check_types::ObligationKind.effect_rep,blot_error::Error.none;},

type_head=>{
return blot_check_types::ObligationKind.type_head,blot_error::Error.none;},

collection=>{
return blot_check_types::ObligationKind.collection,blot_error::Error.none;},

record_merge=>{
return blot_check_types::ObligationKind.record_merge,blot_error::Error.none;},

callee_use=>{
return blot_check_types::ObligationKind.callee_use,blot_error::Error.none;},

type_eq=>{
return blot_check_types::ObligationKind.type_eq,blot_error::Error.none;},

contract=>{
return blot_check_types::ObligationKind.contract,blot_error::Error.none;},

task_receive=>{
return blot_check_types::ObligationKind.task_receive,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_parse_ast::Span)->blot_parse_ast::Span,Error {

var result=default<blot_parse_ast::Span>();

{let copied,error=cloneValue(self_,value.start);if error!=blot_error::Error.none {return result,error;}result.start=copied;}

{let copied,error=cloneValue(self_,value.end);if error!=blot_error::Error.none {return result,error;}result.end=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Node)->blot_check_core::Node,Error {

var result=default<blot_check_core::Node>();

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.op);if error!=blot_error::Error.none {return result,error;}result.op=copied;}

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.a);if error!=blot_error::Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self_,value.b);if error!=blot_error::Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self_,value.c);if error!=blot_error::Error.none {return result,error;}result.c=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Tag)->blot_check_core::Tag,Error {

match value {

invalid=>{
return blot_check_core::Tag.invalid,blot_error::Error.none;},

constant=>{
return blot_check_core::Tag.constant,blot_error::Error.none;},

reference=>{
return blot_check_core::Tag.reference,blot_error::Error.none;},

scalar=>{
return blot_check_core::Tag.scalar,blot_error::Error.none;},

logical=>{
return blot_check_core::Tag.logical,blot_error::Error.none;},

call=>{
return blot_check_core::Tag.call,blot_error::Error.none;},

if_value=>{
return blot_check_core::Tag.if_value,blot_error::Error.none;},

block_=>{
return blot_check_core::Tag.block_,blot_error::Error.none;},

suite=>{
return blot_check_core::Tag.suite,blot_error::Error.none;},

bind=>{
return blot_check_core::Tag.bind,blot_error::Error.none;},

return_=>{
return blot_check_core::Tag.return_,blot_error::Error.none;},

if_stmt=>{
return blot_check_core::Tag.if_stmt,blot_error::Error.none;},

product=>{
return blot_check_core::Tag.product,blot_error::Error.none;},

record=>{
return blot_check_core::Tag.record,blot_error::Error.none;},

construct=>{
return blot_check_core::Tag.construct,blot_error::Error.none;},

project=>{
return blot_check_core::Tag.project,blot_error::Error.none;},

match_=>{
return blot_check_core::Tag.match_,blot_error::Error.none;},

pattern_bind=>{
return blot_check_core::Tag.pattern_bind,blot_error::Error.none;},

update=>{
return blot_check_core::Tag.update,blot_error::Error.none;},

array=>{
return blot_check_core::Tag.array,blot_error::Error.none;},

array_op=>{
return blot_check_core::Tag.array_op,blot_error::Error.none;},

closure=>{
return blot_check_core::Tag.closure,blot_error::Error.none;},

apply=>{
return blot_check_core::Tag.apply,blot_error::Error.none;},

constructor_function=>{
return blot_check_core::Tag.constructor_function,blot_error::Error.none;},

associated=>{
return blot_check_core::Tag.associated,blot_error::Error.none;},

primitive_function=>{
return blot_check_core::Tag.primitive_function,blot_error::Error.none;},

panic=>{
return blot_check_core::Tag.panic,blot_error::Error.none;},

loop_=>{
return blot_check_core::Tag.loop_,blot_error::Error.none;},

break_=>{
return blot_check_core::Tag.break_,blot_error::Error.none;},

type_same=>{
return blot_check_core::Tag.type_same,blot_error::Error.none;},

result_associated=>{
return blot_check_core::Tag.result_associated,blot_error::Error.none;},

type_constructor=>{
return blot_check_core::Tag.type_constructor,blot_error::Error.none;},

resolver_op=>{
return blot_check_core::Tag.resolver_op,blot_error::Error.none;},

operation_value=>{
return blot_check_core::Tag.operation_value,blot_error::Error.none;},

effect_provider=>{
return blot_check_core::Tag.effect_provider,blot_error::Error.none;},

state_provider=>{
return blot_check_core::Tag.state_provider,blot_error::Error.none;},

handle=>{
return blot_check_core::Tag.handle,blot_error::Error.none;},

effect_reflection=>{
return blot_check_core::Tag.effect_reflection,blot_error::Error.none;},

computation=>{
return blot_check_core::Tag.computation,blot_error::Error.none;},

request_loop=>{
return blot_check_core::Tag.request_loop,blot_error::Error.none;},

request_decision=>{
return blot_check_core::Tag.request_decision,blot_error::Error.none;},

record_merge=>{
return blot_check_core::Tag.record_merge,blot_error::Error.none;},

contract_method=>{
return blot_check_core::Tag.contract_method,blot_error::Error.none;},

effect_scope=>{
return blot_check_core::Tag.effect_scope,blot_error::Error.none;},

proof_guard=>{
return blot_check_core::Tag.proof_guard,blot_error::Error.none;},

package_pack=>{
return blot_check_core::Tag.package_pack,blot_error::Error.none;},

package_unpack=>{
return blot_check_core::Tag.package_unpack,blot_error::Error.none;},

staging=>{
return blot_check_core::Tag.staging,blot_error::Error.none;},

usage_borrow=>{
return blot_check_core::Tag.usage_borrow,blot_error::Error.none;},

usage_read=>{
return blot_check_core::Tag.usage_read,blot_error::Error.none;},

resource_scope=>{
return blot_check_core::Tag.resource_scope,blot_error::Error.none;},

usage_share=>{
return blot_check_core::Tag.usage_share,blot_error::Error.none;},

resource_acquire=>{
return blot_check_core::Tag.resource_acquire,blot_error::Error.none;},

resource_release=>{
return blot_check_core::Tag.resource_release,blot_error::Error.none;},

task=>{
return blot_check_core::Tag.task,blot_error::Error.none;},

storage=>{
return blot_check_core::Tag.storage,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::Op)->blot_check_core::Op,Error {

match value {

none=>{
return blot_check_core::Op.none,blot_error::Error.none;},

add=>{
return blot_check_core::Op.add,blot_error::Error.none;},

sub=>{
return blot_check_core::Op.sub,blot_error::Error.none;},

mul=>{
return blot_check_core::Op.mul,blot_error::Error.none;},

div=>{
return blot_check_core::Op.div,blot_error::Error.none;},

rem=>{
return blot_check_core::Op.rem,blot_error::Error.none;},

equal=>{
return blot_check_core::Op.equal,blot_error::Error.none;},

not_equal=>{
return blot_check_core::Op.not_equal,blot_error::Error.none;},

less=>{
return blot_check_core::Op.less,blot_error::Error.none;},

less_equal=>{
return blot_check_core::Op.less_equal,blot_error::Error.none;},

greater=>{
return blot_check_core::Op.greater,blot_error::Error.none;},

greater_equal=>{
return blot_check_core::Op.greater_equal,blot_error::Error.none;},

bit_and=>{
return blot_check_core::Op.bit_and,blot_error::Error.none;},

bit_or=>{
return blot_check_core::Op.bit_or,blot_error::Error.none;},

bit_xor=>{
return blot_check_core::Op.bit_xor,blot_error::Error.none;},

shift_left=>{
return blot_check_core::Op.shift_left,blot_error::Error.none;},

shift_right=>{
return blot_check_core::Op.shift_right,blot_error::Error.none;},

and_=>{
return blot_check_core::Op.and_,blot_error::Error.none;},

or_=>{
return blot_check_core::Op.or_,blot_error::Error.none;},

neg=>{
return blot_check_core::Op.neg,blot_error::Error.none;},

abs=>{
return blot_check_core::Op.abs,blot_error::Error.none;},

ceil=>{
return blot_check_core::Op.ceil,blot_error::Error.none;},

floor=>{
return blot_check_core::Op.floor,blot_error::Error.none;},

trunc=>{
return blot_check_core::Op.trunc,blot_error::Error.none;},

sqrt=>{
return blot_check_core::Op.sqrt,blot_error::Error.none;},

convert_u32_f32=>{
return blot_check_core::Op.convert_u32_f32,blot_error::Error.none;},

convert_f32_u32=>{
return blot_check_core::Op.convert_f32_u32,blot_error::Error.none;},

shift_right_signed=>{
return blot_check_core::Op.shift_right_signed,blot_error::Error.none;},

min=>{
return blot_check_core::Op.min,blot_error::Error.none;},

max=>{
return blot_check_core::Op.max,blot_error::Error.none;},

bit_not=>{
return blot_check_core::Op.bit_not,blot_error::Error.none;},

bit_andnot=>{
return blot_check_core::Op.bit_andnot,blot_error::Error.none;},

any_true=>{
return blot_check_core::Op.any_true,blot_error::Error.none;},

all_true=>{
return blot_check_core::Op.all_true,blot_error::Error.none;},

select=>{
return blot_check_core::Op.select,blot_error::Error.none;},

shuffle=>{
return blot_check_core::Op.shuffle,blot_error::Error.none;},

swizzle=>{
return blot_check_core::Op.swizzle,blot_error::Error.none;},

broadcast=>{
return blot_check_core::Op.broadcast,blot_error::Error.none;},

bits=>{
return blot_check_core::Op.bits,blot_error::Error.none;},

from_bits=>{
return blot_check_core::Op.from_bits,blot_error::Error.none;},

relaxed_madd=>{
return blot_check_core::Op.relaxed_madd,blot_error::Error.none;},

relaxed_nmadd=>{
return blot_check_core::Op.relaxed_nmadd,blot_error::Error.none;},

convert_i32_f32=>{
return blot_check_core::Op.convert_i32_f32,blot_error::Error.none;},

convert_f32_i32=>{
return blot_check_core::Op.convert_f32_i32,blot_error::Error.none;},

continue_=>{
return blot_check_core::Op.continue_,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::Binding)->blot_check_core::Binding,Error {

var result=default<blot_check_core::Binding>();

{let copied,error=cloneValue(self_,value.capability_flow);if error!=blot_error::Error.none {return result,error;}result.capability_flow=copied;}

{let copied,error=cloneValue(self_,value.capability_parameters);if error!=blot_error::Error.none {return result,error;}result.capability_parameters=copied;}

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.initializer);if error!=blot_error::Error.none {return result,error;}result.initializer=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.scheme);if error!=blot_error::Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self_,value.public_variables);if error!=blot_error::Error.none {return result,error;}result.public_variables=copied;}

{let copied,error=cloneValue(self_,value.public_rows);if error!=blot_error::Error.none {return result,error;}result.public_rows=copied;}

{let copied,error=cloneValue(self_,value.has_explicit);if error!=blot_error::Error.none {return result,error;}result.has_explicit=copied;}

{let copied,error=cloneValue(self_,value.body_id);if error!=blot_error::Error.none {return result,error;}result.body_id=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_capability_flow::Contract)->blot_check_capability_flow::Contract,Error {

match value {

unknown=>{
return blot_check_capability_flow::Contract.unknown,blot_error::Error.none;},

identity=>{
return blot_check_capability_flow::Contract.identity,blot_error::Error.none;},

invoke_unit=>{
return blot_check_capability_flow::Contract.invoke_unit,blot_error::Error.none;},

member_unit=>{
return blot_check_capability_flow::Contract.member_unit,blot_error::Error.none;},

invoke_with_capability=>{
return blot_check_capability_flow::Contract.invoke_with_capability,blot_error::Error.none;},

member_first_unit=>{
return blot_check_capability_flow::Contract.member_first_unit,blot_error::Error.none;},

member_second_unit=>{
return blot_check_capability_flow::Contract.member_second_unit,blot_error::Error.none;},

input_shape=>{
return blot_check_capability_flow::Contract.input_shape,blot_error::Error.none;},

consume_task=>{
return blot_check_capability_flow::Contract.consume_task,blot_error::Error.none;},

scope_task=>{
return blot_check_capability_flow::Contract.scope_task,blot_error::Error.none;},

spawn_task=>{
return blot_check_capability_flow::Contract.spawn_task,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_capability_flow::Parameters)->blot_check_capability_flow::Parameters,Error {

var result=default<blot_check_capability_flow::Parameters>();

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.mask);if error!=blot_error::Error.none {return result,error;}result.mask=copied;}

{let copied,error=cloneValue(self_,value.inputs);if error!=blot_error::Error.none {return result,error;}result.inputs=copied;}

{let copied,error=cloneValue(self_,value.invocation_arguments);if error!=blot_error::Error.none {return result,error;}result.invocation_arguments=copied;}

{let copied,error=cloneValue(self_,value.invocation_count);if error!=blot_error::Error.none {return result,error;}result.invocation_count=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_capability_flow::ParameterResult)->blot_check_capability_flow::ParameterResult,Error {

match value {

product=>{
return blot_check_capability_flow::ParameterResult.product,blot_error::Error.none;},

invoke_unit=>{
return blot_check_capability_flow::ParameterResult.invoke_unit,blot_error::Error.none;},

invalid=>{
return blot_check_capability_flow::ParameterResult.invalid,blot_error::Error.none;},

member_closure_unit=>{
return blot_check_capability_flow::ParameterResult.member_closure_unit,blot_error::Error.none;},

captured_unit=>{
return blot_check_capability_flow::ParameterResult.captured_unit,blot_error::Error.none;},

invoke_input=>{
return blot_check_capability_flow::ParameterResult.invoke_input,blot_error::Error.none;},

invoke_inputs=>{
return blot_check_capability_flow::ParameterResult.invoke_inputs,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Kind)->blot_reuse_principal_interface::Kind,Error {

match value {

global=>{
return blot_reuse_principal_interface::Kind.global,blot_error::Error.none;},

local=>{
return blot_reuse_principal_interface::Kind.local,blot_error::Error.none;},

parameter=>{
return blot_reuse_principal_interface::Kind.parameter,blot_error::Error.none;},

external=>{
return blot_reuse_principal_interface::Kind.external,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_types::Scheme)->blot_check_types::Scheme,Error {

var result=default<blot_check_types::Scheme>();

{let copied,error=cloneValue(self_,value.root);if error!=blot_error::Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.row_variables);if error!=blot_error::Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self_,value.closed_rows);if error!=blot_error::Error.none {return result,error;}result.closed_rows=copied;}

{let copied,error=cloneValue(self_,value.obligations);if error!=blot_error::Error.none {return result,error;}result.obligations=copied;}

{let copied,error=cloneValue(self_,value.generative);if error!=blot_error::Error.none {return result,error;}result.generative=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Body)->blot_check_core::Body,Error {

var result=default<blot_check_core::Body>();

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.root);if error!=blot_error::Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.scheme);if error!=blot_error::Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self_,value.closed_rows);if error!=blot_error::Error.none {return result,error;}result.closed_rows=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

{let copied,error=cloneValue(self_,value.declaration_name);if error!=blot_error::Error.none {return result,error;}result.declaration_name=copied;}

{let copied,error=cloneValue(self_,value.export_name);if error!=blot_error::Error.none {return result,error;}result.export_name=copied;}

{let copied,error=cloneValue(self_,value.exported);if error!=blot_error::Error.none {return result,error;}result.exported=copied;}

{let copied,error=cloneValue(self_,value.runtime);if error!=blot_error::Error.none {return result,error;}result.runtime=copied;}

{let copied,error=cloneValue(self_,value.is_function);if error!=blot_error::Error.none {return result,error;}result.is_function=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Parameter)->blot_check_core::Parameter,Error {

var result=default<blot_check_core::Parameter>();

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

{let copied,error=cloneValue(self_,value.inferred);if error!=blot_error::Error.none {return result,error;}result.inferred=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::CallInfo)->blot_check_core::CallInfo,Error {

var result=default<blot_check_core::CallInfo>();

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self_,value.callee_type);if error!=blot_error::Error.none {return result,error;}result.callee_type=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Merge)->blot_check_core::Merge,Error {

var result=default<blot_check_core::Merge>();

{let copied,error=cloneValue(self_,value.node);if error!=blot_error::Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self_,value.result);if error!=blot_error::Error.none {return result,error;}result.result=copied;}

{let copied,error=cloneValue(self_,value.then_binding);if error!=blot_error::Error.none {return result,error;}result.then_binding=copied;}

{let copied,error=cloneValue(self_,value.else_binding);if error!=blot_error::Error.none {return result,error;}result.else_binding=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Obligation)->blot_check_core::Obligation,Error {

var result=default<blot_check_core::Obligation>();

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.result);if error!=blot_error::Error.none {return result,error;}result.result=copied;}

{let copied,error=cloneValue(self_,value.other);if error!=blot_error::Error.none {return result,error;}result.other=copied;}

{let copied,error=cloneValue(self_,value.signature);if error!=blot_error::Error.none {return result,error;}result.signature=copied;}

{let copied,error=cloneValue(self_,value.operator);if error!=blot_error::Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.explicit);if error!=blot_error::Error.none {return result,error;}result.explicit=copied;}

{let copied,error=cloneValue(self_,value.qualification_span);if error!=blot_error::Error.none {return result,error;}result.qualification_span=copied;}

{let copied,error=cloneValue(self_,value.qualification_unit);if error!=blot_error::Error.none {return result,error;}result.qualification_unit=copied;}

{let copied,error=cloneValue(self_,value.diagnostic_name);if error!=blot_error::Error.none {return result,error;}result.diagnostic_name=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Nominal)->blot_check_core::Nominal,Error {

var result=default<blot_check_core::Nominal>();

{let copied,error=cloneValue(self_,value.affine);if error!=blot_error::Error.none {return result,error;}result.affine=copied;}

{let copied,error=cloneValue(self_,value.has_usage);if error!=blot_error::Error.none {return result,error;}result.has_usage=copied;}

{let copied,error=cloneValue(self_,value.closed_storage);if error!=blot_error::Error.none {return result,error;}result.closed_storage=copied;}

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.is_opaque);if error!=blot_error::Error.none {return result,error;}result.is_opaque=copied;}

{let copied,error=cloneValue(self_,value.storage);if error!=blot_error::Error.none {return result,error;}result.storage=copied;}

{let copied,error=cloneValue(self_,value.diagnostic_name);if error!=blot_error::Error.none {return result,error;}result.diagnostic_name=copied;}

{let copied,error=cloneValue(self_,value.diagnostic_origin);if error!=blot_error::Error.none {return result,error;}result.diagnostic_origin=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.constructors);if error!=blot_error::Error.none {return result,error;}result.constructors=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_backend_opaque_storage::Storage)->blot_backend_opaque_storage::Storage,Error {

var result=default<blot_backend_opaque_storage::Storage>();

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.parameter);if error!=blot_error::Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self_,value.selector);if error!=blot_error::Error.none {return result,error;}result.selector=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_backend_opaque_storage::Kind)->blot_backend_opaque_storage::Kind,Error {

match value {

unknown=>{
return blot_backend_opaque_storage::Kind.unknown,blot_error::Error.none;},

unit=>{
return blot_backend_opaque_storage::Kind.unit,blot_error::Error.none;},

boolean=>{
return blot_backend_opaque_storage::Kind.boolean,blot_error::Error.none;},

unsigned32=>{
return blot_backend_opaque_storage::Kind.unsigned32,blot_error::Error.none;},

floating32=>{
return blot_backend_opaque_storage::Kind.floating32,blot_error::Error.none;},

reference=>{
return blot_backend_opaque_storage::Kind.reference,blot_error::Error.none;},

parameter=>{
return blot_backend_opaque_storage::Kind.parameter,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::OperationName)->blot_check_core::OperationName,Error {

var result=default<blot_check_core::OperationName>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.diagnostic_name);if error!=blot_error::Error.none {return result,error;}result.diagnostic_name=copied;}

{let copied,error=cloneValue(self_,value.diagnostic_origin);if error!=blot_error::Error.none {return result,error;}result.diagnostic_origin=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.parameter);if error!=blot_error::Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self_,value.result);if error!=blot_error::Error.none {return result,error;}result.result=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Constructor)->blot_check_core::Constructor,Error {

var result=default<blot_check_core::Constructor>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.nominal);if error!=blot_error::Error.none {return result,error;}result.nominal=copied;}

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.scheme);if error!=blot_error::Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self_,value.payload);if error!=blot_error::Error.none {return result,error;}result.payload=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Projection)->blot_check_core::Projection,Error {

var result=default<blot_check_core::Projection>();

{let copied,error=cloneValue(self_,value.nominal);if error!=blot_error::Error.none {return result,error;}result.nominal=copied;}

{let copied,error=cloneValue(self_,value.field);if error!=blot_error::Error.none {return result,error;}result.field=copied;}

{let copied,error=cloneValue(self_,value.source_type);if error!=blot_error::Error.none {return result,error;}result.source_type=copied;}

{let copied,error=cloneValue(self_,value.result_type);if error!=blot_error::Error.none {return result,error;}result.result_type=copied;}

{let copied,error=cloneValue(self_,value.variants);if error!=blot_error::Error.none {return result,error;}result.variants=copied;}

{let copied,error=cloneValue(self_,value.diagnostic_point);if error!=blot_error::Error.none {return result,error;}result.diagnostic_point=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::ProjectionVariant)->blot_check_core::ProjectionVariant,Error {

var result=default<blot_check_core::ProjectionVariant>();

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.field);if error!=blot_error::Error.none {return result,error;}result.field=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Pattern)->blot_check_core::Pattern,Error {

var result=default<blot_check_core::Pattern>();

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.a);if error!=blot_error::Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self_,value.b);if error!=blot_error::Error.none {return result,error;}result.b=copied;}

{let copied,error=cloneValue(self_,value.c);if error!=blot_error::Error.none {return result,error;}result.c=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::PatternTag)->blot_check_core::PatternTag,Error {

match value {

invalid=>{
return blot_check_core::PatternTag.invalid,blot_error::Error.none;},

wildcard=>{
return blot_check_core::PatternTag.wildcard,blot_error::Error.none;},

bind=>{
return blot_check_core::PatternTag.bind,blot_error::Error.none;},

constant=>{
return blot_check_core::PatternTag.constant,blot_error::Error.none;},

value=>{
return blot_check_core::PatternTag.value,blot_error::Error.none;},

product=>{
return blot_check_core::PatternTag.product,blot_error::Error.none;},

constructor=>{
return blot_check_core::PatternTag.constructor,blot_error::Error.none;},

record_payload=>{
return blot_check_core::PatternTag.record_payload,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::PatternRow)->blot_check_core::PatternRow,Error {

var result=default<blot_check_core::PatternRow>();

{let copied,error=cloneValue(self_,value.patterns);if error!=blot_error::Error.none {return result,error;}result.patterns=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::MatchArm)->blot_check_core::MatchArm,Error {

var result=default<blot_check_core::MatchArm>();

{let copied,error=cloneValue(self_,value.rows);if error!=blot_error::Error.none {return result,error;}result.rows=copied;}

{let copied,error=cloneValue(self_,value.guard_);if error!=blot_error::Error.none {return result,error;}result.guard_=copied;}

{let copied,error=cloneValue(self_,value.body);if error!=blot_error::Error.none {return result,error;}result.body=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::MatchInfo)->blot_check_core::MatchInfo,Error {

var result=default<blot_check_core::MatchInfo>();

{let copied,error=cloneValue(self_,value.inputs);if error!=blot_error::Error.none {return result,error;}result.inputs=copied;}

{let copied,error=cloneValue(self_,value.arms);if error!=blot_error::Error.none {return result,error;}result.arms=copied;}

{let copied,error=cloneValue(self_,value.statement);if error!=blot_error::Error.none {return result,error;}result.statement=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::UpdateInfo)->blot_check_core::UpdateInfo,Error {

var result=default<blot_check_core::UpdateInfo>();

{let copied,error=cloneValue(self_,value.root);if error!=blot_error::Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self_,value.path);if error!=blot_error::Error.none {return result,error;}result.path=copied;}

{let copied,error=cloneValue(self_,value.value);if error!=blot_error::Error.none {return result,error;}result.value=copied;}

{let copied,error=cloneValue(self_,value.self_binding);if error!=blot_error::Error.none {return result,error;}result.self_binding=copied;}

{let copied,error=cloneValue(self_,value.selectors);if error!=blot_error::Error.none {return result,error;}result.selectors=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::UpdateStep)->blot_check_core::UpdateStep,Error {

var result=default<blot_check_core::UpdateStep>();

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.projection);if error!=blot_error::Error.none {return result,error;}result.projection=copied;}

{let copied,error=cloneValue(self_,value.index);if error!=blot_error::Error.none {return result,error;}result.index=copied;}

{let copied,error=cloneValue(self_,value.source_type);if error!=blot_error::Error.none {return result,error;}result.source_type=copied;}

{let copied,error=cloneValue(self_,value.result_type);if error!=blot_error::Error.none {return result,error;}result.result_type=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::UpdateKind)->blot_check_core::UpdateKind,Error {

match value {

field=>{
return blot_check_core::UpdateKind.field,blot_error::Error.none;},

index=>{
return blot_check_core::UpdateKind.index,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::ClosureInfo)->blot_check_core::ClosureInfo,Error {

var result=default<blot_check_core::ClosureInfo>();

{let copied,error=cloneValue(self_,value.qualifier);if error!=blot_error::Error.none {return result,error;}result.qualifier=copied;}

{let copied,error=cloneValue(self_,value.body);if error!=blot_error::Error.none {return result,error;}result.body=copied;}

{let copied,error=cloneValue(self_,value.parameter);if error!=blot_error::Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self_,value.captures);if error!=blot_error::Error.none {return result,error;}result.captures=copied;}

{let copied,error=cloneValue(self_,value.function_type);if error!=blot_error::Error.none {return result,error;}result.function_type=copied;}

{let copied,error=cloneValue(self_,value.closed_rows);if error!=blot_error::Error.none {return result,error;}result.closed_rows=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Associated)->blot_check_core::Associated,Error {

var result=default<blot_check_core::Associated>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.member);if error!=blot_error::Error.none {return result,error;}result.member=copied;}

{let copied,error=cloneValue(self_,value.operator);if error!=blot_error::Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Contract)->blot_check_core::Contract,Error {

var result=default<blot_check_core::Contract>();

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.row_variables);if error!=blot_error::Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self_,value.predicates);if error!=blot_error::Error.none {return result,error;}result.predicates=copied;}

{let copied,error=cloneValue(self_,value.members);if error!=blot_error::Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self_,value.requires_implementation);if error!=blot_error::Error.none {return result,error;}result.requires_implementation=copied;}

{let copied,error=cloneValue(self_,value.row_parameter_names);if error!=blot_error::Error.none {return result,error;}result.row_parameter_names=copied;}

{let copied,error=cloneValue(self_,value.row_parameters);if error!=blot_error::Error.none {return result,error;}result.row_parameters=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::ContractMember)->blot_reuse_principal_interface::ContractMember,Error {

var result=default<blot_reuse_principal_interface::ContractMember>();

{let copied,error=cloneValue(self_,value.contract);if error!=blot_error::Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.root);if error!=blot_error::Error.none {return result,error;}result.root=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::ContractMemberKind)->blot_reuse_principal_interface::ContractMemberKind,Error {

match value {

defined_type=>{
return blot_reuse_principal_interface::ContractMemberKind.defined_type,blot_error::Error.none;},

abstract_type=>{
return blot_reuse_principal_interface::ContractMemberKind.abstract_type,blot_error::Error.none;},

value=>{
return blot_reuse_principal_interface::ContractMemberKind.value,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Implementation)->blot_reuse_principal_interface::Implementation,Error {

var result=default<blot_reuse_principal_interface::Implementation>();

{let copied,error=cloneValue(self_,value.origin_span);if error!=blot_error::Error.none {return result,error;}result.origin_span=copied;}

{let copied,error=cloneValue(self_,value.declaration);if error!=blot_error::Error.none {return result,error;}result.declaration=copied;}

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.contract);if error!=blot_error::Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self_,value.head);if error!=blot_error::Error.none {return result,error;}result.head=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.parameter_names);if error!=blot_error::Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self_,value.row_variables);if error!=blot_error::Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self_,value.row_parameter_names);if error!=blot_error::Error.none {return result,error;}result.row_parameter_names=copied;}

{let copied,error=cloneValue(self_,value.row_parameters);if error!=blot_error::Error.none {return result,error;}result.row_parameters=copied;}

{let copied,error=cloneValue(self_,value.predicates);if error!=blot_error::Error.none {return result,error;}result.predicates=copied;}

{let copied,error=cloneValue(self_,value.members);if error!=blot_error::Error.none {return result,error;}result.members=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::ImplementationMember)->blot_reuse_principal_interface::ImplementationMember,Error {

var result=default<blot_reuse_principal_interface::ImplementationMember>();

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.root);if error!=blot_error::Error.none {return result,error;}result.root=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::ImplementationMemberKind)->blot_reuse_principal_interface::ImplementationMemberKind,Error {

match value {

type_=>{
return blot_reuse_principal_interface::ImplementationMemberKind.type_,blot_error::Error.none;},

value=>{
return blot_reuse_principal_interface::ImplementationMemberKind.value,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::ExternalTarget)->blot_reuse_principal_interface::ExternalTarget,Error {

var result=default<blot_reuse_principal_interface::ExternalTarget>();

{let copied,error=cloneValue(self_,value.unit);if error!=blot_error::Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::MemberTemplate)->blot_reuse_principal_interface::MemberTemplate,Error {

var result=default<blot_reuse_principal_interface::MemberTemplate>();

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.contract);if error!=blot_error::Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.arguments);if error!=blot_error::Error.none {return result,error;}result.arguments=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::SelectedProof)->blot_reuse_principal_interface::SelectedProof,Error {

var result=default<blot_reuse_principal_interface::SelectedProof>();

{let copied,error=cloneValue(self_,value.predicate_target);if error!=blot_error::Error.none {return result,error;}result.predicate_target=copied;}

{let copied,error=cloneValue(self_,value.context);if error!=blot_error::Error.none {return result,error;}result.context=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.predicate);if error!=blot_error::Error.none {return result,error;}result.predicate=copied;}

{let copied,error=cloneValue(self_,value.implementation);if error!=blot_error::Error.none {return result,error;}result.implementation=copied;}

{let copied,error=cloneValue(self_,value.contract);if error!=blot_error::Error.none {return result,error;}result.contract=copied;}

{let copied,error=cloneValue(self_,value.arguments);if error!=blot_error::Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self_,value.members);if error!=blot_error::Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self_,value.prerequisites);if error!=blot_error::Error.none {return result,error;}result.prerequisites=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::SelectedProofKind)->blot_reuse_principal_interface::SelectedProofKind,Error {

match value {

implementation=>{
return blot_reuse_principal_interface::SelectedProofKind.implementation,blot_error::Error.none;},

predicate=>{
return blot_reuse_principal_interface::SelectedProofKind.predicate,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::SelectedUse)->blot_check_core::SelectedUse,Error {

var result=default<blot_check_core::SelectedUse>();

{let copied,error=cloneValue(self_,value.node);if error!=blot_error::Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self_,value.proof);if error!=blot_error::Error.none {return result,error;}result.proof=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::DictionarySelection)->blot_check_core::DictionarySelection,Error {

var result=default<blot_check_core::DictionarySelection>();

{let copied,error=cloneValue(self_,value.owner);if error!=blot_error::Error.none {return result,error;}result.owner=copied;}

{let copied,error=cloneValue(self_,value.quantifier);if error!=blot_error::Error.none {return result,error;}result.quantifier=copied;}

{let copied,error=cloneValue(self_,value.goal);if error!=blot_error::Error.none {return result,error;}result.goal=copied;}

{let copied,error=cloneValue(self_,value.proof);if error!=blot_error::Error.none {return result,error;}result.proof=copied;}

{let copied,error=cloneValue(self_,value.members);if error!=blot_error::Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self_,value.contents);if error!=blot_error::Error.none {return result,error;}result.contents=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::DictionaryProof)->blot_check_core::DictionaryProof,Error {

match value {

selected payload=>{
let value,error_value=cloneValue(self_,payload.value);if error_value!=blot_error::Error.none {return default<blot_check_core::DictionaryProof>(),error_value;}
return blot_check_core::DictionaryProof.selected {value:value, ..},blot_error::Error.none;},

given payload=>{
let value,error_value=cloneValue(self_,payload.value);if error_value!=blot_error::Error.none {return default<blot_check_core::DictionaryProof>(),error_value;}
return blot_check_core::DictionaryProof.given {value:value, ..},blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::DictionaryGiven)->blot_check_core::DictionaryGiven,Error {

var result=default<blot_check_core::DictionaryGiven>();

{let copied,error=cloneValue(self_,value.opening);if error!=blot_error::Error.none {return result,error;}result.opening=copied;}

{let copied,error=cloneValue(self_,value.introduction);if error!=blot_error::Error.none {return result,error;}result.introduction=copied;}

{let copied,error=cloneValue(self_,value.quantifier);if error!=blot_error::Error.none {return result,error;}result.quantifier=copied;}

{let copied,error=cloneValue(self_,value.goal);if error!=blot_error::Error.none {return result,error;}result.goal=copied;}

{let copied,error=cloneValue(self_,value.arguments);if error!=blot_error::Error.none {return result,error;}result.arguments=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::DictionaryUse)->blot_check_core::DictionaryUse,Error {

var result=default<blot_check_core::DictionaryUse>();

{let copied,error=cloneValue(self_,value.node);if error!=blot_error::Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

{let copied,error=cloneValue(self_,value.opening);if error!=blot_error::Error.none {return result,error;}result.opening=copied;}

{let copied,error=cloneValue(self_,value.introduction);if error!=blot_error::Error.none {return result,error;}result.introduction=copied;}

{let copied,error=cloneValue(self_,value.quantifier);if error!=blot_error::Error.none {return result,error;}result.quantifier=copied;}

{let copied,error=cloneValue(self_,value.goal);if error!=blot_error::Error.none {return result,error;}result.goal=copied;}

{let copied,error=cloneValue(self_,value.member);if error!=blot_error::Error.none {return result,error;}result.member=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Primitive)->blot_check_core::Primitive,Error {

var result=default<blot_check_core::Primitive>();

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.op);if error!=blot_error::Error.none {return result,error;}result.op=copied;}

{let copied,error=cloneValue(self_,value.array_op);if error!=blot_error::Error.none {return result,error;}result.array_op=copied;}

{let copied,error=cloneValue(self_,value.arity);if error!=blot_error::Error.none {return result,error;}result.arity=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::PrimitiveKind)->blot_check_core::PrimitiveKind,Error {

match value {

scalar=>{
return blot_check_core::PrimitiveKind.scalar,blot_error::Error.none;},

array=>{
return blot_check_core::PrimitiveKind.array,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_backend_collection_ops::Op)->blot_backend_collection_ops::Op,Error {

match value {

length=>{
return blot_backend_collection_ops::Op.length,blot_error::Error.none;},

get=>{
return blot_backend_collection_ops::Op.get,blot_error::Error.none;},

set=>{
return blot_backend_collection_ops::Op.set,blot_error::Error.none;},

fill=>{
return blot_backend_collection_ops::Op.fill,blot_error::Error.none;},

generate=>{
return blot_backend_collection_ops::Op.generate,blot_error::Error.none;},

append=>{
return blot_backend_collection_ops::Op.append,blot_error::Error.none;},

prepend=>{
return blot_backend_collection_ops::Op.prepend,blot_error::Error.none;},

identity=>{
return blot_backend_collection_ops::Op.identity,blot_error::Error.none;},

convert=>{
return blot_backend_collection_ops::Op.convert,blot_error::Error.none;},

cursor=>{
return blot_backend_collection_ops::Op.cursor,blot_error::Error.none;},

cursor_has=>{
return blot_backend_collection_ops::Op.cursor_has,blot_error::Error.none;},

cursor_value=>{
return blot_backend_collection_ops::Op.cursor_value,blot_error::Error.none;},

cursor_advance=>{
return blot_backend_collection_ops::Op.cursor_advance,blot_error::Error.none;},

concat=>{
return blot_backend_collection_ops::Op.concat,blot_error::Error.none;},

slice=>{
return blot_backend_collection_ops::Op.slice,blot_error::Error.none;},

simd_load=>{
return blot_backend_collection_ops::Op.simd_load,blot_error::Error.none;},

simd_store=>{
return blot_backend_collection_ops::Op.simd_store,blot_error::Error.none;},

flatten=>{
return blot_backend_collection_ops::Op.flatten,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::LoopInfo)->blot_check_core::LoopInfo,Error {

var result=default<blot_check_core::LoopInfo>();

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.first);if error!=blot_error::Error.none {return result,error;}result.first=copied;}

{let copied,error=cloneValue(self_,value.end);if error!=blot_error::Error.none {return result,error;}result.end=copied;}

{let copied,error=cloneValue(self_,value.pattern);if error!=blot_error::Error.none {return result,error;}result.pattern=copied;}

{let copied,error=cloneValue(self_,value.body);if error!=blot_error::Error.none {return result,error;}result.body=copied;}

{let copied,error=cloneValue(self_,value.carries);if error!=blot_error::Error.none {return result,error;}result.carries=copied;}

{let copied,error=cloneValue(self_,value.can_exit);if error!=blot_error::Error.none {return result,error;}result.can_exit=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::LoopKind)->blot_check_core::LoopKind,Error {

match value {

forever=>{
return blot_check_core::LoopKind.forever,blot_error::Error.none;},

range=>{
return blot_check_core::LoopKind.range,blot_error::Error.none;},

array=>{
return blot_check_core::LoopKind.array,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::LoopCarry)->blot_check_core::LoopCarry,Error {

var result=default<blot_check_core::LoopCarry>();

{let copied,error=cloneValue(self_,value.incoming);if error!=blot_error::Error.none {return result,error;}result.incoming=copied;}

{let copied,error=cloneValue(self_,value.iteration);if error!=blot_error::Error.none {return result,error;}result.iteration=copied;}

{let copied,error=cloneValue(self_,value.backedge);if error!=blot_error::Error.none {return result,error;}result.backedge=copied;}

{let copied,error=cloneValue(self_,value.outgoing);if error!=blot_error::Error.none {return result,error;}result.outgoing=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::ResolverInfo)->blot_check_core::ResolverInfo,Error {

var result=default<blot_check_core::ResolverInfo>();

{let copied,error=cloneValue(self_,value.operation);if error!=blot_error::Error.none {return result,error;}result.operation=copied;}

{let copied,error=cloneValue(self_,value.resolver);if error!=blot_error::Error.none {return result,error;}result.resolver=copied;}

{let copied,error=cloneValue(self_,value.arguments);if error!=blot_error::Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self_,value.member);if error!=blot_error::Error.none {return result,error;}result.member=copied;}

{let copied,error=cloneValue(self_,value.method);if error!=blot_error::Error.none {return result,error;}result.method=copied;}

{let copied,error=cloneValue(self_,value.method_type);if error!=blot_error::Error.none {return result,error;}result.method_type=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::ResolverOperation)->blot_check_core::ResolverOperation,Error {

match value {

monad=>{
return blot_check_core::ResolverOperation.monad,blot_error::Error.none;},

pure=>{
return blot_check_core::ResolverOperation.pure,blot_error::Error.none;},

bind=>{
return blot_check_core::ResolverOperation.bind,blot_error::Error.none;},

forward=>{
return blot_check_core::ResolverOperation.forward,blot_error::Error.none;},

iterate=>{
return blot_check_core::ResolverOperation.iterate,blot_error::Error.none;},

run=>{
return blot_check_core::ResolverOperation.run,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_check_core::OperationValue)->blot_check_core::OperationValue,Error {

var result=default<blot_check_core::OperationValue>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.arguments);if error!=blot_error::Error.none {return result,error;}result.arguments=copied;}

{let copied,error=cloneValue(self_,value.signature);if error!=blot_error::Error.none {return result,error;}result.signature=copied;}

{let copied,error=cloneValue(self_,value.witness);if error!=blot_error::Error.none {return result,error;}result.witness=copied;}

{let copied,error=cloneValue(self_,value.witness_result);if error!=blot_error::Error.none {return result,error;}result.witness_result=copied;}

{let copied,error=cloneValue(self_,value.instance);if error!=blot_error::Error.none {return result,error;}result.instance=copied;}

{let copied,error=cloneValue(self_,value.capability);if error!=blot_error::Error.none {return result,error;}result.capability=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::HandleEffects)->blot_check_core::HandleEffects,Error {

var result=default<blot_check_core::HandleEffects>();

{let copied,error=cloneValue(self_,value.node);if error!=blot_error::Error.none {return result,error;}result.node=copied;}

{let copied,error=cloneValue(self_,value.first);if error!=blot_error::Error.none {return result,error;}result.first=copied;}

{let copied,error=cloneValue(self_,value.second);if error!=blot_error::Error.none {return result,error;}result.second=copied;}

{let copied,error=cloneValue(self_,value.extended);if error!=blot_error::Error.none {return result,error;}result.extended=copied;}

{let copied,error=cloneValue(self_,value.residual);if error!=blot_error::Error.none {return result,error;}result.residual=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Diagnostic)->blot_check_core::Diagnostic,Error {

var result=default<blot_check_core::Diagnostic>();

{let copied,error=cloneValue(self_,value.code);if error!=blot_error::Error.none {return result,error;}result.code=copied;}

{let copied,error=cloneValue(self_,value.span);if error!=blot_error::Error.none {return result,error;}result.span=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_core::Code)->blot_check_core::Code,Error {

match value {

unchecked=>{
return blot_check_core::Code.unchecked,blot_error::Error.none;},

unsupported=>{
return blot_check_core::Code.unsupported,blot_error::Error.none;},

unresolved_binding=>{
return blot_check_core::Code.unresolved_binding,blot_error::Error.none;},

invalid_call=>{
return blot_check_core::Code.invalid_call,blot_error::Error.none;},

complexity=>{
return blot_check_core::Code.complexity,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Interface)->blot_reuse_principal_interface::Interface,Error {

var result=default<blot_reuse_principal_interface::Interface>();

{let copied,error=cloneValue(self_,value.has_rank_contracts);if error!=blot_error::Error.none {return result,error;}result.has_rank_contracts=copied;}

{let copied,error=cloneValue(self_,value.has_usage_contracts);if error!=blot_error::Error.none {return result,error;}result.has_usage_contracts=copied;}

{let copied,error=cloneValue(self_,value.has_numeric_proofs);if error!=blot_error::Error.none {return result,error;}result.has_numeric_proofs=copied;}

{let copied,error=cloneValue(self_,value.proof_contracts);if error!=blot_error::Error.none {return result,error;}result.proof_contracts=copied;}

{let copied,error=cloneValue(self_,value.capability_contracts);if error!=blot_error::Error.none {return result,error;}result.capability_contracts=copied;}

{let copied,error=cloneValue(self_,value.unit);if error!=blot_error::Error.none {return result,error;}result.unit=copied;}

{let copied,error=cloneValue(self_,value.graph);if error!=blot_error::Error.none {return result,error;}result.graph=copied;}

{let copied,error=cloneValue(self_,value.patterns);if error!=blot_error::Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self_,value.bindings);if error!=blot_error::Error.none {return result,error;}result.bindings=copied;}

{let copied,error=cloneValue(self_,value.obligations);if error!=blot_error::Error.none {return result,error;}result.obligations=copied;}

{let copied,error=cloneValue(self_,value.obligation_spans);if error!=blot_error::Error.none {return result,error;}result.obligation_spans=copied;}

{let copied,error=cloneValue(self_,value.nominals);if error!=blot_error::Error.none {return result,error;}result.nominals=copied;}

{let copied,error=cloneValue(self_,value.constructors);if error!=blot_error::Error.none {return result,error;}result.constructors=copied;}

{let copied,error=cloneValue(self_,value.effect_families);if error!=blot_error::Error.none {return result,error;}result.effect_families=copied;}

{let copied,error=cloneValue(self_,value.effect_templates);if error!=blot_error::Error.none {return result,error;}result.effect_templates=copied;}

{let copied,error=cloneValue(self_,value.associated);if error!=blot_error::Error.none {return result,error;}result.associated=copied;}

{let copied,error=cloneValue(self_,value.contracts);if error!=blot_error::Error.none {return result,error;}result.contracts=copied;}

{let copied,error=cloneValue(self_,value.contract_predicates);if error!=blot_error::Error.none {return result,error;}result.contract_predicates=copied;}

{let copied,error=cloneValue(self_,value.contract_members);if error!=blot_error::Error.none {return result,error;}result.contract_members=copied;}

{let copied,error=cloneValue(self_,value.implementations);if error!=blot_error::Error.none {return result,error;}result.implementations=copied;}

{let copied,error=cloneValue(self_,value.implementation_predicates);if error!=blot_error::Error.none {return result,error;}result.implementation_predicates=copied;}

{let copied,error=cloneValue(self_,value.implementation_members);if error!=blot_error::Error.none {return result,error;}result.implementation_members=copied;}

{let copied,error=cloneValue(self_,value.member_templates);if error!=blot_error::Error.none {return result,error;}result.member_templates=copied;}

{let copied,error=cloneValue(self_,value.selected_proofs);if error!=blot_error::Error.none {return result,error;}result.selected_proofs=copied;}

{let copied,error=cloneValue(self_,value.selected_members);if error!=blot_error::Error.none {return result,error;}result.selected_members=copied;}

{let copied,error=cloneValue(self_,value.selected_edges);if error!=blot_error::Error.none {return result,error;}result.selected_edges=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_frozen_types::Graph)->blot_check_frozen_types::Graph,Error {

var result=default<blot_check_frozen_types::Graph>();

{let copied,error=cloneValue(self_,value.nodes);if error!=blot_error::Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self_,value.extra);if error!=blot_error::Error.none {return result,error;}result.extra=copied;}

{let copied,error=cloneValue(self_,value.rows);if error!=blot_error::Error.none {return result,error;}result.rows=copied;}

{let copied,error=cloneValue(self_,value.labels);if error!=blot_error::Error.none {return result,error;}result.labels=copied;}

{let copied,error=cloneValue(self_,value.operations);if error!=blot_error::Error.none {return result,error;}result.operations=copied;}

{let copied,error=cloneValue(self_,value.row_variable_count);if error!=blot_error::Error.none {return result,error;}result.row_variable_count=copied;}

{let copied,error=cloneValue(self_,value.quantifier_goals);if error!=blot_error::Error.none {return result,error;}result.quantifier_goals=copied;}

{let copied,error=cloneValue(self_,value.quantifier_obligations);if error!=blot_error::Error.none {return result,error;}result.quantifier_obligations=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_frozen_types::PatternGraph)->blot_check_frozen_types::PatternGraph,Error {

var result=default<blot_check_frozen_types::PatternGraph>();

{let copied,error=cloneValue(self_,value.nodes);if error!=blot_error::Error.none {return result,error;}result.nodes=copied;}

{let copied,error=cloneValue(self_,value.extra);if error!=blot_error::Error.none {return result,error;}result.extra=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_parameter_patterns::Node)->blot_check_parameter_patterns::Node,Error {

var result=default<blot_check_parameter_patterns::Node>();

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.a);if error!=blot_error::Error.none {return result,error;}result.a=copied;}

{let copied,error=cloneValue(self_,value.b);if error!=blot_error::Error.none {return result,error;}result.b=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_check_parameter_patterns::Kind)->blot_check_parameter_patterns::Kind,Error {

match value {

binding=>{
return blot_check_parameter_patterns::Kind.binding,blot_error::Error.none;},

tuple=>{
return blot_check_parameter_patterns::Kind.tuple,blot_error::Error.none;},

array=>{
return blot_check_parameter_patterns::Kind.array,blot_error::Error.none;},

record=>{
return blot_check_parameter_patterns::Kind.record,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Binding)->blot_reuse_principal_interface::Binding,Error {

var result=default<blot_reuse_principal_interface::Binding>();

{let copied,error=cloneValue(self_,value.capability_flow);if error!=blot_error::Error.none {return result,error;}result.capability_flow=copied;}

{let copied,error=cloneValue(self_,value.capability_parameters);if error!=blot_error::Error.none {return result,error;}result.capability_parameters=copied;}

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.named_function);if error!=blot_error::Error.none {return result,error;}result.named_function=copied;}

{let copied,error=cloneValue(self_,value.ty);if error!=blot_error::Error.none {return result,error;}result.ty=copied;}

{let copied,error=cloneValue(self_,value.scheme);if error!=blot_error::Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self_,value.external);if error!=blot_error::Error.none {return result,error;}result.external=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Nominal)->blot_reuse_principal_interface::Nominal,Error {

var result=default<blot_reuse_principal_interface::Nominal>();

{let copied,error=cloneValue(self_,value.affine);if error!=blot_error::Error.none {return result,error;}result.affine=copied;}

{let copied,error=cloneValue(self_,value.has_usage);if error!=blot_error::Error.none {return result,error;}result.has_usage=copied;}

{let copied,error=cloneValue(self_,value.closed_storage);if error!=blot_error::Error.none {return result,error;}result.closed_storage=copied;}

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.is_opaque);if error!=blot_error::Error.none {return result,error;}result.is_opaque=copied;}

{let copied,error=cloneValue(self_,value.storage);if error!=blot_error::Error.none {return result,error;}result.storage=copied;}

{let copied,error=cloneValue(self_,value.declaration);if error!=blot_error::Error.none {return result,error;}result.declaration=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.patterns);if error!=blot_error::Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self_,value.parameter_names);if error!=blot_error::Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self_,value.constructors);if error!=blot_error::Error.none {return result,error;}result.constructors=copied;}

{let copied,error=cloneValue(self_,value.alias);if error!=blot_error::Error.none {return result,error;}result.alias=copied;}

{let copied,error=cloneValue(self_,value.alias_rows);if error!=blot_error::Error.none {return result,error;}result.alias_rows=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Constructor)->blot_reuse_principal_interface::Constructor,Error {

var result=default<blot_reuse_principal_interface::Constructor>();

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.nominal);if error!=blot_error::Error.none {return result,error;}result.nominal=copied;}

{let copied,error=cloneValue(self_,value.tag);if error!=blot_error::Error.none {return result,error;}result.tag=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.scheme);if error!=blot_error::Error.none {return result,error;}result.scheme=copied;}

{let copied,error=cloneValue(self_,value.payload);if error!=blot_error::Error.none {return result,error;}result.payload=copied;}

{let copied,error=cloneValue(self_,value.declared_record);if error!=blot_error::Error.none {return result,error;}result.declared_record=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::EffectFamily)->blot_reuse_principal_interface::EffectFamily,Error {

var result=default<blot_reuse_principal_interface::EffectFamily>();

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.callable);if error!=blot_error::Error.none {return result,error;}result.callable=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.patterns);if error!=blot_error::Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self_,value.parameter_names);if error!=blot_error::Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self_,value.operations);if error!=blot_error::Error.none {return result,error;}result.operations=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::EffectTemplate)->blot_reuse_principal_interface::EffectTemplate,Error {

var result=default<blot_reuse_principal_interface::EffectTemplate>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.family);if error!=blot_error::Error.none {return result,error;}result.family=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.parameter);if error!=blot_error::Error.none {return result,error;}result.parameter=copied;}

{let copied,error=cloneValue(self_,value.result);if error!=blot_error::Error.none {return result,error;}result.result=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Associated)->blot_reuse_principal_interface::Associated,Error {

var result=default<blot_reuse_principal_interface::Associated>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.member);if error!=blot_error::Error.none {return result,error;}result.member=copied;}

{let copied,error=cloneValue(self_,value.operator);if error!=blot_error::Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self_,value.binding);if error!=blot_error::Error.none {return result,error;}result.binding=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_principal_interface::Contract)->blot_reuse_principal_interface::Contract,Error {

var result=default<blot_reuse_principal_interface::Contract>();

{let copied,error=cloneValue(self_,value.declaration);if error!=blot_error::Error.none {return result,error;}result.declaration=copied;}

{let copied,error=cloneValue(self_,value.private);if error!=blot_error::Error.none {return result,error;}result.private=copied;}

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.parameters);if error!=blot_error::Error.none {return result,error;}result.parameters=copied;}

{let copied,error=cloneValue(self_,value.variables);if error!=blot_error::Error.none {return result,error;}result.variables=copied;}

{let copied,error=cloneValue(self_,value.patterns);if error!=blot_error::Error.none {return result,error;}result.patterns=copied;}

{let copied,error=cloneValue(self_,value.parameter_names);if error!=blot_error::Error.none {return result,error;}result.parameter_names=copied;}

{let copied,error=cloneValue(self_,value.row_variables);if error!=blot_error::Error.none {return result,error;}result.row_variables=copied;}

{let copied,error=cloneValue(self_,value.row_parameter_names);if error!=blot_error::Error.none {return result,error;}result.row_parameter_names=copied;}

{let copied,error=cloneValue(self_,value.row_parameters);if error!=blot_error::Error.none {return result,error;}result.row_parameters=copied;}

{let copied,error=cloneValue(self_,value.predicates);if error!=blot_error::Error.none {return result,error;}result.predicates=copied;}

{let copied,error=cloneValue(self_,value.members);if error!=blot_error::Error.none {return result,error;}result.members=copied;}

{let copied,error=cloneValue(self_,value.requires_implementation);if error!=blot_error::Error.none {return result,error;}result.requires_implementation=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::Module)->blot_reuse_frozen_dependency::Module,Error {

var result=default<blot_reuse_frozen_dependency::Module>();

{let copied,error=cloneValue(self_,value.identity);if error!=blot_error::Error.none {return result,error;}result.identity=copied;}

{let copied,error=cloneValue(self_,value.imports);if error!=blot_error::Error.none {return result,error;}result.imports=copied;}

{let copied,error=cloneValue(self_,value.implicit_prelude);if error!=blot_error::Error.none {return result,error;}result.implicit_prelude=copied;}

{let copied,error=cloneValue(self_,value.source_imports);if error!=blot_error::Error.none {return result,error;}result.source_imports=copied;}

{let copied,error=cloneValue(self_,value.core);if error!=blot_error::Error.none {return result,error;}result.core=copied;}

{let copied,error=cloneValue(self_,value.interface);if error!=blot_error::Error.none {return result,error;}result.interface=copied;}

{let copied,error=cloneValue(self_,value.exports);if error!=blot_error::Error.none {return result,error;}result.exports=copied;}

{let copied,error=cloneValue(self_,value.fixities);if error!=blot_error::Error.none {return result,error;}result.fixities=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::Identity)->blot_reuse_frozen_dependency::Identity,Error {

var result=default<blot_reuse_frozen_dependency::Identity>();

{let copied,error=cloneValue(self_,value.normalized_path);if error!=blot_error::Error.none {return result,error;}result.normalized_path=copied;}

{let copied,error=cloneValue(self_,value.source_digest);if error!=blot_error::Error.none {return result,error;}result.source_digest=copied;}

{let copied,error=cloneValue(self_,value.source_bytes);if error!=blot_error::Error.none {return result,error;}result.source_bytes=copied;}

{let copied,error=cloneValue(self_,value.prelude);if error!=blot_error::Error.none {return result,error;}result.prelude=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::ImportResolution)->blot_reuse_frozen_dependency::ImportResolution,Error {

var result=default<blot_reuse_frozen_dependency::ImportResolution>();

{let copied,error=cloneValue(self_,value.path);if error!=blot_error::Error.none {return result,error;}result.path=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::Export)->blot_reuse_frozen_dependency::Export,Error {

var result=default<blot_reuse_frozen_dependency::Export>();

{let copied,error=cloneValue(self_,value.name);if error!=blot_error::Error.none {return result,error;}result.name=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self_,value.kind);if error!=blot_error::Error.none {return result,error;}result.kind=copied;}

{let copied,error=cloneValue(self_,value.catalog);if error!=blot_error::Error.none {return result,error;}result.catalog=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::ExportKind)->blot_reuse_frozen_dependency::ExportKind,Error {

match value {

value=>{
return blot_reuse_frozen_dependency::ExportKind.value,blot_error::Error.none;},

nominal=>{
return blot_reuse_frozen_dependency::ExportKind.nominal,blot_error::Error.none;},

constructor=>{
return blot_reuse_frozen_dependency::ExportKind.constructor,blot_error::Error.none;},

effect_family=>{
return blot_reuse_frozen_dependency::ExportKind.effect_family,blot_error::Error.none;},

contract=>{
return blot_reuse_frozen_dependency::ExportKind.contract,blot_error::Error.none;},

implementation=>{
return blot_reuse_frozen_dependency::ExportKind.implementation,blot_error::Error.none;},

}

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::Fixity)->blot_reuse_frozen_dependency::Fixity,Error {

var result=default<blot_reuse_frozen_dependency::Fixity>();

{let copied,error=cloneValue(self_,value.operator);if error!=blot_error::Error.none {return result,error;}result.operator=copied;}

{let copied,error=cloneValue(self_,value.target);if error!=blot_error::Error.none {return result,error;}result.target=copied;}

{let copied,error=cloneValue(self_,value.precedence);if error!=blot_error::Error.none {return result,error;}result.precedence=copied;}

{let copied,error=cloneValue(self_,value.association);if error!=blot_error::Error.none {return result,error;}result.association=copied;}

{let copied,error=cloneValue(self_,value.named);if error!=blot_error::Error.none {return result,error;}result.named=copied;}

{let copied,error=cloneValue(self_,value.producer);if error!=blot_error::Error.none {return result,error;}result.producer=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::FrozenDependency)->blot_reuse_frozen_dependency::FrozenDependency,Error {

var result=default<blot_reuse_frozen_dependency::FrozenDependency>();

{let copied,error=cloneValue(self_,value.symbols);if error!=blot_error::Error.none {return result,error;}result.symbols=copied;}

{let copied,error=cloneValue(self_,value.modules);if error!=blot_error::Error.none {return result,error;}result.modules=copied;}

return result,blot_error::Error.none;

}

fn cloneValue(self_:Owner&,value:blot_reuse_frozen_dependency::Symbol)->blot_reuse_frozen_dependency::Symbol,Error {

var result=default<blot_reuse_frozen_dependency::Symbol>();

{let copied,error=cloneValue(self_,value.text);if error!=blot_error::Error.none {return result,error;}result.text=copied;}

return result,blot_error::Error.none;

}

fn clone(value:const blot_check_core::Module&)->Owned<blot_check_core::Module>,Error {
 var owner,error=init();if error!=blot_error::Error.none {return default<Owned<blot_check_core::Module>>(),error;}
 let result,error=cloneValue(owner,value);if error!=blot_error::Error.none {owner.deinit();return default<Owned<blot_check_core::Module>>(),error;}return Owned<blot_check_core::Module> {result,owner, ..},blot_error::Error.none;
}

fn clone(value:const blot_reuse_principal_interface::Interface&)->Owned<blot_reuse_principal_interface::Interface>,Error {
 var owner,error=init();if error!=blot_error::Error.none {return default<Owned<blot_reuse_principal_interface::Interface>>(),error;}
 let result,error=cloneValue(owner,value);if error!=blot_error::Error.none {owner.deinit();return default<Owned<blot_reuse_principal_interface::Interface>>(),error;}return Owned<blot_reuse_principal_interface::Interface> {result,owner, ..},blot_error::Error.none;
}

fn clone(value:const blot_reuse_frozen_dependency::Module&)->Owned<blot_reuse_frozen_dependency::Module>,Error {
 var owner,error=init();if error!=blot_error::Error.none {return default<Owned<blot_reuse_frozen_dependency::Module>>(),error;}
 let result,error=cloneValue(owner,value);if error!=blot_error::Error.none {owner.deinit();return default<Owned<blot_reuse_frozen_dependency::Module>>(),error;}return Owned<blot_reuse_frozen_dependency::Module> {result,owner, ..},blot_error::Error.none;
}

fn clone(value:const blot_reuse_frozen_dependency::FrozenDependency&)->Owned<blot_reuse_frozen_dependency::FrozenDependency>,Error {
 var owner,error=init();if error!=blot_error::Error.none {return default<Owned<blot_reuse_frozen_dependency::FrozenDependency>>(),error;}
 let result,error=cloneValue(owner,value);if error!=blot_error::Error.none {owner.deinit();return default<Owned<blot_reuse_frozen_dependency::FrozenDependency>>(),error;}return Owned<blot_reuse_frozen_dependency::FrozenDependency> {result,owner, ..},blot_error::Error.none;
}

// Split existing registered runs without copying a retained module.
struct Mark {owner:u32,generation:u64,head:u32}
fn mark(self_:const Owner&)->Mark {assert(unique(self_));return Mark {self_.lease,self_.generation,leases[self_.lease-1].head, ..};}
fn rollback(self_:Owner&,mark:Mark) {
 assert(unique(self_)&&self_.lease==mark.owner&&self_.generation==mark.generation);
 var check=leases[self_.lease-1].head;while check!=mark.head {assert(check!=0);check=links[check-1].next;}
 while leases[self_.lease-1].head!=mark.head {let head=leases[self_.lease-1].head;let link=links[head-1];leases[self_.lease-1].head=link.next;match link.value {
run_header_module run=>{pool_header_module.free_slice(run.values);},
run_header_path run=>{pool_header_path.free_slice(run.values);},
run_header_digest run=>{pool_header_digest.free_slice(run.values);},
run_header_name run=>{pool_header_name.free_slice(run.values);},
run_header_import run=>{pool_header_import.free_slice(run.values);},
run_header_owner run=>{pool_header_owner.free_slice(run.values);},
run_bool run=>{pool_bool.free_slice(run.values);},


run_u32 run=>{pool_u32.free_slice(run.values);},

run_blot_check_numeric_proof_terms__Kind run=>{pool_blot_check_numeric_proof_terms__Kind.free_slice(run.values);},

run_blot_check_numeric_proof_terms__Term run=>{pool_blot_check_numeric_proof_terms__Term.free_slice(run.values);},

run_blot_check_numeric_proof_contracts__Requirement run=>{pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run.values);},

run_blot_check_numeric_proof_headers__Named run=>{pool_blot_check_numeric_proof_headers__Named.free_slice(run.values);},

run_blot_check_capability_contracts__Term run=>{pool_blot_check_capability_contracts__Term.free_slice(run.values);},

run_blot_check_capability_contracts__Binding run=>{pool_blot_check_capability_contracts__Binding.free_slice(run.values);},

run_blot_check_core__FieldName run=>{pool_blot_check_core__FieldName.free_slice(run.values);},

run_blot_check_core__RuntimeName run=>{pool_blot_check_core__RuntimeName.free_slice(run.values);},

run_blot_check_core__DeclarationDependencies run=>{pool_blot_check_core__DeclarationDependencies.free_slice(run.values);},

run_blot_check_core__BindingRef run=>{pool_blot_check_core__BindingRef.free_slice(run.values);},

run_blot_check_core__DependencyMember run=>{pool_blot_check_core__DependencyMember.free_slice(run.values);},

run_blot_check_core__ErasedDeclarationReference run=>{pool_blot_check_core__ErasedDeclarationReference.free_slice(run.values);},

run_blot_check_core__RequestLoopInfo run=>{pool_blot_check_core__RequestLoopInfo.free_slice(run.values);},

run_blot_check_core__RequestArm run=>{pool_blot_check_core__RequestArm.free_slice(run.values);},

run_blot_check_types__Node run=>{pool_blot_check_types__Node.free_slice(run.values);},

run_blot_check_effects__Row run=>{pool_blot_check_effects__Row.free_slice(run.values);},

run_blot_check_types__Operation run=>{pool_blot_check_types__Operation.free_slice(run.values);},

run_blot_check_types__QuantifierGoals run=>{pool_blot_check_types__QuantifierGoals.free_slice(run.values);},

run_blot_check_types__Obligation run=>{pool_blot_check_types__Obligation.free_slice(run.values);},

run_blot_check_core__Node run=>{pool_blot_check_core__Node.free_slice(run.values);},

run_blot_parse_ast__Span run=>{pool_blot_parse_ast__Span.free_slice(run.values);},

run_blot_check_core__Binding run=>{pool_blot_check_core__Binding.free_slice(run.values);},

run_blot_check_core__Body run=>{pool_blot_check_core__Body.free_slice(run.values);},

run_blot_check_core__Parameter run=>{pool_blot_check_core__Parameter.free_slice(run.values);},

run_blot_check_core__CallInfo run=>{pool_blot_check_core__CallInfo.free_slice(run.values);},

run_blot_check_core__Merge run=>{pool_blot_check_core__Merge.free_slice(run.values);},

run_blot_check_core__List run=>{pool_blot_check_core__List.free_slice(run.values);},

run_u8 run=>{pool_u8.free_slice(run.values);},

run_blot_check_core__Obligation run=>{pool_blot_check_core__Obligation.free_slice(run.values);},

run_blot_check_core__Nominal run=>{pool_blot_check_core__Nominal.free_slice(run.values);},

run_blot_check_core__OperationName run=>{pool_blot_check_core__OperationName.free_slice(run.values);},

run_blot_check_core__Constructor run=>{pool_blot_check_core__Constructor.free_slice(run.values);},

run_blot_check_core__Projection run=>{pool_blot_check_core__Projection.free_slice(run.values);},

run_blot_check_core__ProjectionVariant run=>{pool_blot_check_core__ProjectionVariant.free_slice(run.values);},

run_blot_check_core__Pattern run=>{pool_blot_check_core__Pattern.free_slice(run.values);},

run_blot_check_core__PatternRow run=>{pool_blot_check_core__PatternRow.free_slice(run.values);},

run_blot_check_core__MatchArm run=>{pool_blot_check_core__MatchArm.free_slice(run.values);},

run_blot_check_core__MatchInfo run=>{pool_blot_check_core__MatchInfo.free_slice(run.values);},

run_blot_check_core__UpdateInfo run=>{pool_blot_check_core__UpdateInfo.free_slice(run.values);},

run_blot_check_core__UpdateStep run=>{pool_blot_check_core__UpdateStep.free_slice(run.values);},

run_blot_check_core__ClosureInfo run=>{pool_blot_check_core__ClosureInfo.free_slice(run.values);},

run_blot_check_core__Associated run=>{pool_blot_check_core__Associated.free_slice(run.values);},

run_blot_check_core__Contract run=>{pool_blot_check_core__Contract.free_slice(run.values);},

run_blot_reuse_principal_interface__ContractMember run=>{pool_blot_reuse_principal_interface__ContractMember.free_slice(run.values);},

run_blot_reuse_principal_interface__Implementation run=>{pool_blot_reuse_principal_interface__Implementation.free_slice(run.values);},

run_blot_reuse_principal_interface__ImplementationMember run=>{pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run.values);},

run_blot_reuse_principal_interface__MemberTemplate run=>{pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run.values);},

run_blot_reuse_principal_interface__SelectedProof run=>{pool_blot_reuse_principal_interface__SelectedProof.free_slice(run.values);},

run_blot_check_core__SelectedUse run=>{pool_blot_check_core__SelectedUse.free_slice(run.values);},

run_blot_check_core__DictionarySelection run=>{pool_blot_check_core__DictionarySelection.free_slice(run.values);},

run_blot_check_core__DictionaryUse run=>{pool_blot_check_core__DictionaryUse.free_slice(run.values);},

run_blot_check_core__Primitive run=>{pool_blot_check_core__Primitive.free_slice(run.values);},

run_blot_check_core__LoopInfo run=>{pool_blot_check_core__LoopInfo.free_slice(run.values);},

run_blot_check_core__LoopCarry run=>{pool_blot_check_core__LoopCarry.free_slice(run.values);},

run_blot_check_core__ResolverInfo run=>{pool_blot_check_core__ResolverInfo.free_slice(run.values);},

run_blot_check_core__OperationValue run=>{pool_blot_check_core__OperationValue.free_slice(run.values);},

run_blot_check_core__HandleEffects run=>{pool_blot_check_core__HandleEffects.free_slice(run.values);},

run_blot_check_core__Diagnostic run=>{pool_blot_check_core__Diagnostic.free_slice(run.values);},

run_blot_check_parameter_patterns__Node run=>{pool_blot_check_parameter_patterns__Node.free_slice(run.values);},

run_blot_reuse_principal_interface__Binding run=>{pool_blot_reuse_principal_interface__Binding.free_slice(run.values);},

run_blot_reuse_principal_interface__Nominal run=>{pool_blot_reuse_principal_interface__Nominal.free_slice(run.values);},

run_blot_reuse_principal_interface__Constructor run=>{pool_blot_reuse_principal_interface__Constructor.free_slice(run.values);},

run_blot_reuse_principal_interface__EffectFamily run=>{pool_blot_reuse_principal_interface__EffectFamily.free_slice(run.values);},

run_blot_reuse_principal_interface__EffectTemplate run=>{pool_blot_reuse_principal_interface__EffectTemplate.free_slice(run.values);},

run_blot_reuse_principal_interface__Associated run=>{pool_blot_reuse_principal_interface__Associated.free_slice(run.values);},

run_blot_reuse_principal_interface__Contract run=>{pool_blot_reuse_principal_interface__Contract.free_slice(run.values);},

run_blot_reuse_frozen_dependency__ImportResolution run=>{pool_blot_reuse_frozen_dependency__ImportResolution.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Export run=>{pool_blot_reuse_frozen_dependency__Export.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Fixity run=>{pool_blot_reuse_frozen_dependency__Fixity.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Symbol run=>{pool_blot_reuse_frozen_dependency__Symbol.free_slice(run.values);},

run_blot_reuse_frozen_dependency__Module run=>{pool_blot_reuse_frozen_dependency__Module.free_slice(run.values);},

}links.free(head-1);}
}

fn detach(self_:Owner&,destination:Owner&,values:const u32[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_u32 run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_u32 run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const u32[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_terms::Kind[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_terms__Kind run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_numeric_proof_terms__Kind run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_terms::Kind[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_terms::Term[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_terms__Term run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_numeric_proof_terms__Term run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_terms::Term[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_contracts::Requirement[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_contracts__Requirement run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_numeric_proof_contracts__Requirement run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_contracts::Requirement[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_headers::Named[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_headers__Named run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_numeric_proof_headers__Named run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_numeric_proof_headers::Named[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_capability_contracts::Term[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_capability_contracts__Term run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_capability_contracts__Term run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_capability_contracts::Term[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_capability_contracts::Binding[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_capability_contracts__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_capability_contracts__Binding run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_capability_contracts::Binding[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::FieldName[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__FieldName run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__FieldName run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::FieldName[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::RuntimeName[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RuntimeName run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__RuntimeName run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::RuntimeName[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::DeclarationDependencies[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DeclarationDependencies run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__DeclarationDependencies run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::DeclarationDependencies[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::BindingRef[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__BindingRef run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__BindingRef run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::BindingRef[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::DependencyMember[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DependencyMember run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__DependencyMember run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::DependencyMember[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::ErasedDeclarationReference[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ErasedDeclarationReference run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__ErasedDeclarationReference run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::ErasedDeclarationReference[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::RequestLoopInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RequestLoopInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__RequestLoopInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::RequestLoopInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::RequestArm[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RequestArm run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__RequestArm run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::RequestArm[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_types::Node[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Node run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_types__Node run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_types::Node[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_effects::Row[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_effects__Row run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_effects__Row run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_effects::Row[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_types::Operation[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Operation run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_types__Operation run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_types::Operation[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_types::QuantifierGoals[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__QuantifierGoals run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_types__QuantifierGoals run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_types::QuantifierGoals[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_types::Obligation[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Obligation run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_types__Obligation run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_types::Obligation[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Node[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Node run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Node run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Node[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_parse_ast::Span[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_parse_ast__Span run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_parse_ast__Span run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_parse_ast::Span[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Binding[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Binding run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Binding[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Body[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Body run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Body run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Body[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Parameter[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Parameter run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Parameter run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Parameter[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::CallInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__CallInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__CallInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::CallInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Merge[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Merge run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Merge run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Merge[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::List[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__List run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__List run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::List[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const u8[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_u8 run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_u8 run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const u8[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Obligation[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Obligation run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Obligation run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Obligation[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Nominal[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Nominal run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Nominal run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Nominal[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::OperationName[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__OperationName run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__OperationName run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::OperationName[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Constructor[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Constructor run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Constructor run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Constructor[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Projection[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Projection run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Projection run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Projection[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::ProjectionVariant[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ProjectionVariant run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__ProjectionVariant run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::ProjectionVariant[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Pattern[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Pattern run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Pattern run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Pattern[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::PatternRow[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__PatternRow run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__PatternRow run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::PatternRow[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::MatchArm[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__MatchArm run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__MatchArm run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::MatchArm[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::MatchInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__MatchInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__MatchInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::MatchInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::UpdateInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__UpdateInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__UpdateInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::UpdateInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::UpdateStep[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__UpdateStep run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__UpdateStep run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::UpdateStep[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::ClosureInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ClosureInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__ClosureInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::ClosureInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Associated[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Associated run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Associated run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Associated[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Contract[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Contract run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Contract run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Contract[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::ContractMember[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__ContractMember run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__ContractMember run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::ContractMember[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Implementation[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Implementation run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__Implementation run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Implementation[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::ImplementationMember[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__ImplementationMember run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__ImplementationMember run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::ImplementationMember[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::MemberTemplate[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__MemberTemplate run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__MemberTemplate run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::MemberTemplate[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::SelectedProof[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__SelectedProof run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__SelectedProof run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::SelectedProof[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::SelectedUse[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__SelectedUse run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__SelectedUse run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::SelectedUse[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::DictionarySelection[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DictionarySelection run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__DictionarySelection run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::DictionarySelection[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::DictionaryUse[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DictionaryUse run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__DictionaryUse run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::DictionaryUse[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Primitive[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Primitive run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Primitive run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Primitive[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::LoopInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__LoopInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__LoopInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::LoopInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::LoopCarry[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__LoopCarry run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__LoopCarry run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::LoopCarry[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::ResolverInfo[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ResolverInfo run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__ResolverInfo run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::ResolverInfo[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::OperationValue[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__OperationValue run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__OperationValue run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::OperationValue[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::HandleEffects[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__HandleEffects run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__HandleEffects run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::HandleEffects[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_core::Diagnostic[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Diagnostic run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_core__Diagnostic run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_core::Diagnostic[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_check_parameter_patterns::Node[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_parameter_patterns__Node run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_check_parameter_patterns__Node run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_check_parameter_patterns::Node[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Binding[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__Binding run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Binding[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Nominal[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Nominal run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__Nominal run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Nominal[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Constructor[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Constructor run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__Constructor run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Constructor[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::EffectFamily[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__EffectFamily run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__EffectFamily run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::EffectFamily[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::EffectTemplate[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__EffectTemplate run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__EffectTemplate run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::EffectTemplate[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Associated[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Associated run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__Associated run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Associated[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Contract[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Contract run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_principal_interface__Contract run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_principal_interface::Contract[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::ImportResolution[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__ImportResolution run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_frozen_dependency__ImportResolution run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::ImportResolution[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Export[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Export run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_frozen_dependency__Export run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Export[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Fixity[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Fixity run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_frozen_dependency__Fixity run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Fixity[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Symbol[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Symbol run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_frozen_dependency__Symbol run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Symbol[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn detach(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Module[:]) {
 assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {return;}
 // An alias already transferred to this module keeps the same one owner.
 var next=leases[destination.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_frozen_dependency__Module run=>{if blot_support::same_slice_identity(run.values,values) {return;}},_=>{}}}
 var previous:u32=0;next=leases[self_.lease-1].head;
 while next!=0 {let current=next;let link=links[current-1];next=link.next;var found=false;match link.value {run_blot_reuse_frozen_dependency__Module run=>{found=run.values .== values;},_=>{}}
 if found {if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;return;}previous=current;
 }abort("partitioned payload view must name this private owner's exact live run");
}
fn partitionInto(self_:Owner&,destination:Owner&,values:const blot_reuse_frozen_dependency::Module[:]) {self_.detach(destination,values);for value in values {partitionInto(self_,destination,value);}}

fn partitionInto(self_:Owner&,destination:Owner&,value:bool) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:f32) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:f64) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:i16) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:i32) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:i64) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:i8) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:u16) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:u32) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:u64) {}

fn partitionInto(self_:Owner&,destination:Owner&,value:u8) {}

fn partitionInto(self_:Owner&,destination:Owner&,values:u8[32]) {for value in values {partitionInto(self_,destination,value);}}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_support::Option<blot_check_numeric_proof_terms::Proposition>) {if value.present {partitionInto(self_,destination,value.value);}}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_support::Option<blot_parse_ast::Span>) {if value.present {partitionInto(self_,destination,value.value);}}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_support::Option<blot_reuse_principal_interface::ExternalTarget>) {if value.present {partitionInto(self_,destination,value.value);}}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Module) {
partitionInto(self_,destination,value.package_payloads);


partitionInto(self_,destination,value.has_rank_contracts);

partitionInto(self_,destination,value.has_usage_contracts);

partitionInto(self_,destination,value.has_numeric_proofs);

partitionInto(self_,destination,value.proof_contracts);

partitionInto(self_,destination,value.capability_contracts);

partitionInto(self_,destination,value.field_names);

partitionInto(self_,destination,value.runtime_names);

partitionInto(self_,destination,value.source_names);

partitionInto(self_,destination,value.declaration_dependencies);

partitionInto(self_,destination,value.dependency_references);

partitionInto(self_,destination,value.dependency_members);

partitionInto(self_,destination,value.erased_declaration_references);

partitionInto(self_,destination,value.request_loops);

partitionInto(self_,destination,value.request_arms);

partitionInto(self_,destination,value.tag_calls);

partitionInto(self_,destination,value.unit);

partitionInto(self_,destination,value.types);

partitionInto(self_,destination,value.nodes);

partitionInto(self_,destination,value.spans);

partitionInto(self_,destination,value.extra);

partitionInto(self_,destination,value.bindings);

partitionInto(self_,destination,value.bodies);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.references);

partitionInto(self_,destination,value.calls);

partitionInto(self_,destination,value.merges);

partitionInto(self_,destination,value.merge_ranges);

partitionInto(self_,destination,value.names);

partitionInto(self_,destination,value.obligations);

partitionInto(self_,destination,value.nominals);

partitionInto(self_,destination,value.operation_names);

partitionInto(self_,destination,value.constructors);

partitionInto(self_,destination,value.projections);

partitionInto(self_,destination,value.projection_variants);

partitionInto(self_,destination,value.patterns);

partitionInto(self_,destination,value.pattern_rows);

partitionInto(self_,destination,value.match_arms);

partitionInto(self_,destination,value.matches);

partitionInto(self_,destination,value.updates);

partitionInto(self_,destination,value.update_steps);

partitionInto(self_,destination,value.closures);

partitionInto(self_,destination,value.associated);

partitionInto(self_,destination,value.contracts);

partitionInto(self_,destination,value.contract_members);

partitionInto(self_,destination,value.implementations);

partitionInto(self_,destination,value.implementation_members);

partitionInto(self_,destination,value.member_templates);

partitionInto(self_,destination,value.selected_proofs);

partitionInto(self_,destination,value.selected_members);

partitionInto(self_,destination,value.selected_edges);

partitionInto(self_,destination,value.selected_uses);

partitionInto(self_,destination,value.dictionary_selections);

partitionInto(self_,destination,value.dictionary_uses);

partitionInto(self_,destination,value.primitives);

partitionInto(self_,destination,value.loops);

partitionInto(self_,destination,value.loop_carries);

partitionInto(self_,destination,value.resolver_ops);

partitionInto(self_,destination,value.operation_values);

partitionInto(self_,destination,value.handle_effects);

partitionInto(self_,destination,value.dispatch_signatures);

partitionInto(self_,destination,value.diagnostics);

partitionInto(self_,destination,value.body_lowerings);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_headers::Named) {

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.header);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_headers::Owned) {

partitionInto(self_,destination,value.arity);

partitionInto(self_,destination,value.value_slots);

partitionInto(self_,destination,value.proof_slots);

partitionInto(self_,destination,value.values);

partitionInto(self_,destination,value.operands);

partitionInto(self_,destination,value.requirements);

partitionInto(self_,destination,value.result);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_terms::Kind) {

match value {

unsigned32=>{
},

array=>{
},

list=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_terms::Term) {

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.a);

partitionInto(self_,destination,value.b);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_terms::Tag) {

match value {

literal=>{
},

formal=>{
},

capture=>{
},

version=>{
},

length=>{
},

complement=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_contracts::Requirement) {

partitionInto(self_,destination,value.before);

partitionInto(self_,destination,value.proposition);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_terms::Proposition) {

partitionInto(self_,destination,value.relation);

partitionInto(self_,destination,value.left);

partitionInto(self_,destination,value.right);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_numeric_proof_terms::Relation) {

match value {

eq=>{
},

lt=>{
},

le=>{
},

add_fits=>{
},

sub_fits=>{
},

index=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_contracts::Collection) {

partitionInto(self_,destination,value.nodes);

partitionInto(self_,destination,value.words);

partitionInto(self_,destination,value.bindings);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_contracts::Term) {

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.a);

partitionInto(self_,destination,value.b);

partitionInto(self_,destination,value.c);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_contracts::Tag) {

match value {

empty=>{
},

unknown=>{
},

parameter=>{
},

authority=>{
},

captures=>{
},

product=>{
},

record=>{
},

wrapped=>{
},

join=>{
},

project=>{
},

elements=>{
},

argument=>{
},

callable=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_contracts::Binding) {

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.root);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::FieldName) {

partitionInto(self_,destination,value.symbol);

partitionInto(self_,destination,value.spelling);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Name) {

partitionInto(self_,destination,value.start);

partitionInto(self_,destination,value.len);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::RuntimeName) {

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.point);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::DeclarationDependencies) {

partitionInto(self_,destination,value.references);

partitionInto(self_,destination,value.members);

partitionInto(self_,destination,value.runtime_metadata);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::List) {

partitionInto(self_,destination,value.start);

partitionInto(self_,destination,value.len);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::BindingRef) {

partitionInto(self_,destination,value.unit);

partitionInto(self_,destination,value.binding);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::DependencyMember) {

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.operator);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::Operator) {

match value {

none=>{
},

add=>{
},

sub=>{
},

mul=>{
},

div=>{
},

rem=>{
},

equal=>{
},

not_equal=>{
},

less=>{
},

less_equal=>{
},

greater=>{
},

greater_equal=>{
},

bit_and=>{
},

bit_or=>{
},

bit_xor=>{
},

shift_left=>{
},

shift_right=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::ErasedDeclarationReference) {

partitionInto(self_,destination,value.node);

partitionInto(self_,destination,value.target);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::RequestLoopInfo) {

partitionInto(self_,destination,value.computation);

partitionInto(self_,destination,value.action_type);

partitionInto(self_,destination,value.value_type);

partitionInto(self_,destination,value.result_type);

partitionInto(self_,destination,value.state_type);

partitionInto(self_,destination,value.arms);

partitionInto(self_,destination,value.completion_pattern);

partitionInto(self_,destination,value.completion_body);

partitionInto(self_,destination,value.completion_state_bindings);

partitionInto(self_,destination,value.carries);

partitionInto(self_,destination,value.return_target);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::RequestArm) {

partitionInto(self_,destination,value.operation);

partitionInto(self_,destination,value.callback);

partitionInto(self_,destination,value.selector);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Types) {

partitionInto(self_,destination,value.nodes);

partitionInto(self_,destination,value.extra);

partitionInto(self_,destination,value.effects);

partitionInto(self_,destination,value.operations);

partitionInto(self_,destination,value.quantifier_goals);

partitionInto(self_,destination,value.quantifier_obligations);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::Node) {

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.closed_height);

partitionInto(self_,destination,value.closed_generation);

partitionInto(self_,destination,value.a);

partitionInto(self_,destination,value.b);

partitionInto(self_,destination,value.c);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::Tag) {

match value {

absent=>{
},

unit=>{
},

boolean=>{
},

unsigned32=>{
},

floating32=>{
},

never=>{
},

variable=>{
},

function=>{
},

product=>{
},

record=>{
},

nominal=>{
},

array=>{
},

list=>{
},

cursor=>{
},

type_constructor=>{
},

resolver=>{
},

provider=>{
},

state_provider=>{
},

projection=>{
},

scoped=>{
},

instance_selection=>{
},

erased_proof=>{
},

forall=>{
},

existential=>{
},

bound=>{
},

rigid=>{
},

usage=>{
},

instance_version=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::EffectRows) {

partitionInto(self_,destination,value.rows);

partitionInto(self_,destination,value.labels);

partitionInto(self_,destination,value.variable_count);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_effects::Row) {

partitionInto(self_,destination,value.labels);

partitionInto(self_,destination,value.tail);

partitionInto(self_,destination,value.cursor);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_effects::List) {

partitionInto(self_,destination,value.start);

partitionInto(self_,destination,value.len);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_effects::Tail) {

match value {

closed=>{
},

variable payload=>{
partitionInto(self_,destination,payload.value);
},

parameter payload=>{
partitionInto(self_,destination,payload.value);
},

formal payload=>{
partitionInto(self_,destination,payload.value);
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::Operation) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.arguments);

partitionInto(self_,destination,value.instance);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::NominalIdentity) {

partitionInto(self_,destination,value.unit);

partitionInto(self_,destination,value.decl);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::List) {

partitionInto(self_,destination,value.start);

partitionInto(self_,destination,value.len);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::QuantifierGoals) {

partitionInto(self_,destination,value.owner);

partitionInto(self_,destination,value.goals);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::Obligation) {

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.source);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.result);

partitionInto(self_,destination,value.other);

partitionInto(self_,destination,value.signature);

partitionInto(self_,destination,value.operator);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.explicit);

partitionInto(self_,destination,value.qualification_span);

partitionInto(self_,destination,value.qualification_unit);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::ObligationKind) {

match value {

arithmetic=>{
},

ordered=>{
},

equality=>{
},

integer=>{
},

field=>{
},

writable_field=>{
},

dispatch=>{
},

result_dispatch=>{
},

monad_factory=>{
},

resolver_dispatch=>{
},

resolver_shape=>{
},

effect_operation=>{
},

effect_handler=>{
},

receiver=>{
},

update=>{
},

type_rep=>{
},

effect_rep=>{
},

type_head=>{
},

collection=>{
},

record_merge=>{
},

callee_use=>{
},

type_eq=>{
},

contract=>{
},

task_receive=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_parse_ast::Span) {

partitionInto(self_,destination,value.start);

partitionInto(self_,destination,value.end);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Node) {

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.op);

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.a);

partitionInto(self_,destination,value.b);

partitionInto(self_,destination,value.c);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Tag) {

match value {

invalid=>{
},

constant=>{
},

reference=>{
},

scalar=>{
},

logical=>{
},

call=>{
},

if_value=>{
},

block_=>{
},

suite=>{
},

bind=>{
},

return_=>{
},

if_stmt=>{
},

product=>{
},

record=>{
},

construct=>{
},

project=>{
},

match_=>{
},

pattern_bind=>{
},

update=>{
},

array=>{
},

array_op=>{
},

closure=>{
},

apply=>{
},

constructor_function=>{
},

associated=>{
},

primitive_function=>{
},

panic=>{
},

loop_=>{
},

break_=>{
},

type_same=>{
},

result_associated=>{
},

type_constructor=>{
},

resolver_op=>{
},

operation_value=>{
},

effect_provider=>{
},

state_provider=>{
},

handle=>{
},

effect_reflection=>{
},

computation=>{
},

request_loop=>{
},

request_decision=>{
},

record_merge=>{
},

contract_method=>{
},

effect_scope=>{
},

proof_guard=>{
},

package_pack=>{
},

package_unpack=>{
},

staging=>{
},

usage_borrow=>{
},

usage_read=>{
},

resource_scope=>{
},

usage_share=>{
},

resource_acquire=>{
},

resource_release=>{
},

task=>{
},

storage=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Op) {

match value {

none=>{
},

add=>{
},

sub=>{
},

mul=>{
},

div=>{
},

rem=>{
},

equal=>{
},

not_equal=>{
},

less=>{
},

less_equal=>{
},

greater=>{
},

greater_equal=>{
},

bit_and=>{
},

bit_or=>{
},

bit_xor=>{
},

shift_left=>{
},

shift_right=>{
},

and_=>{
},

or_=>{
},

neg=>{
},

abs=>{
},

ceil=>{
},

floor=>{
},

trunc=>{
},

sqrt=>{
},

convert_u32_f32=>{
},

convert_f32_u32=>{
},

shift_right_signed=>{
},

min=>{
},

max=>{
},

bit_not=>{
},

bit_andnot=>{
},

any_true=>{
},

all_true=>{
},

select=>{
},

shuffle=>{
},

swizzle=>{
},

broadcast=>{
},

bits=>{
},

from_bits=>{
},

relaxed_madd=>{
},

relaxed_nmadd=>{
},

convert_i32_f32=>{
},

convert_f32_i32=>{
},

continue_=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Binding) {

partitionInto(self_,destination,value.capability_flow);

partitionInto(self_,destination,value.capability_parameters);

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.initializer);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.scheme);

partitionInto(self_,destination,value.public_variables);

partitionInto(self_,destination,value.public_rows);

partitionInto(self_,destination,value.has_explicit);

partitionInto(self_,destination,value.body_id);

partitionInto(self_,destination,value.target);

partitionInto(self_,destination,value.span);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_flow::Contract) {

match value {

unknown=>{
},

identity=>{
},

invoke_unit=>{
},

member_unit=>{
},

invoke_with_capability=>{
},

member_first_unit=>{
},

member_second_unit=>{
},

input_shape=>{
},

consume_task=>{
},

scope_task=>{
},

spawn_task=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_flow::Parameters) {

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.mask);

partitionInto(self_,destination,value.inputs);

partitionInto(self_,destination,value.invocation_arguments);

partitionInto(self_,destination,value.invocation_count);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_capability_flow::ParameterResult) {

match value {

product=>{
},

invoke_unit=>{
},

invalid=>{
},

member_closure_unit=>{
},

captured_unit=>{
},

invoke_input=>{
},

invoke_inputs=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Kind) {

match value {

global=>{
},

local=>{
},

parameter=>{
},

external=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_types::Scheme) {

partitionInto(self_,destination,value.root);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.row_variables);

partitionInto(self_,destination,value.closed_rows);

partitionInto(self_,destination,value.obligations);

partitionInto(self_,destination,value.generative);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Body) {

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.root);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.scheme);

partitionInto(self_,destination,value.closed_rows);

partitionInto(self_,destination,value.span);

partitionInto(self_,destination,value.declaration_name);

partitionInto(self_,destination,value.export_name);

partitionInto(self_,destination,value.exported);

partitionInto(self_,destination,value.runtime);

partitionInto(self_,destination,value.is_function);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Parameter) {

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.span);

partitionInto(self_,destination,value.inferred);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::CallInfo) {

partitionInto(self_,destination,value.target);

partitionInto(self_,destination,value.callee_type);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Merge) {

partitionInto(self_,destination,value.node);

partitionInto(self_,destination,value.result);

partitionInto(self_,destination,value.then_binding);

partitionInto(self_,destination,value.else_binding);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Obligation) {

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.span);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.result);

partitionInto(self_,destination,value.other);

partitionInto(self_,destination,value.signature);

partitionInto(self_,destination,value.operator);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.explicit);

partitionInto(self_,destination,value.qualification_span);

partitionInto(self_,destination,value.qualification_unit);

partitionInto(self_,destination,value.diagnostic_name);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Nominal) {

partitionInto(self_,destination,value.affine);

partitionInto(self_,destination,value.has_usage);

partitionInto(self_,destination,value.closed_storage);

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.is_opaque);

partitionInto(self_,destination,value.storage);

partitionInto(self_,destination,value.diagnostic_name);

partitionInto(self_,destination,value.diagnostic_origin);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.constructors);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_backend_opaque_storage::Storage) {

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.parameter);

partitionInto(self_,destination,value.selector);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_backend_opaque_storage::Kind) {

match value {

unknown=>{
},

unit=>{
},

boolean=>{
},

unsigned32=>{
},

floating32=>{
},

reference=>{
},

parameter=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::OperationName) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.diagnostic_name);

partitionInto(self_,destination,value.diagnostic_origin);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.parameter);

partitionInto(self_,destination,value.result);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Constructor) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.nominal);

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.scheme);

partitionInto(self_,destination,value.payload);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Projection) {

partitionInto(self_,destination,value.nominal);

partitionInto(self_,destination,value.field);

partitionInto(self_,destination,value.source_type);

partitionInto(self_,destination,value.result_type);

partitionInto(self_,destination,value.variants);

partitionInto(self_,destination,value.diagnostic_point);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::ProjectionVariant) {

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.field);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Pattern) {

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.a);

partitionInto(self_,destination,value.b);

partitionInto(self_,destination,value.c);

partitionInto(self_,destination,value.span);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::PatternTag) {

match value {

invalid=>{
},

wildcard=>{
},

bind=>{
},

constant=>{
},

value=>{
},

product=>{
},

constructor=>{
},

record_payload=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::PatternRow) {

partitionInto(self_,destination,value.patterns);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::MatchArm) {

partitionInto(self_,destination,value.rows);

partitionInto(self_,destination,value.guard_);

partitionInto(self_,destination,value.body);

partitionInto(self_,destination,value.span);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::MatchInfo) {

partitionInto(self_,destination,value.inputs);

partitionInto(self_,destination,value.arms);

partitionInto(self_,destination,value.statement);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::UpdateInfo) {

partitionInto(self_,destination,value.root);

partitionInto(self_,destination,value.path);

partitionInto(self_,destination,value.value);

partitionInto(self_,destination,value.self_binding);

partitionInto(self_,destination,value.selectors);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::UpdateStep) {

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.projection);

partitionInto(self_,destination,value.index);

partitionInto(self_,destination,value.source_type);

partitionInto(self_,destination,value.result_type);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::UpdateKind) {

match value {

field=>{
},

index=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::ClosureInfo) {

partitionInto(self_,destination,value.qualifier);

partitionInto(self_,destination,value.body);

partitionInto(self_,destination,value.parameter);

partitionInto(self_,destination,value.captures);

partitionInto(self_,destination,value.function_type);

partitionInto(self_,destination,value.closed_rows);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Associated) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.member);

partitionInto(self_,destination,value.operator);

partitionInto(self_,destination,value.target);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Contract) {

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.row_variables);

partitionInto(self_,destination,value.predicates);

partitionInto(self_,destination,value.members);

partitionInto(self_,destination,value.requires_implementation);

partitionInto(self_,destination,value.row_parameter_names);

partitionInto(self_,destination,value.row_parameters);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::ContractMember) {

partitionInto(self_,destination,value.contract);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.root);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::ContractMemberKind) {

match value {

defined_type=>{
},

abstract_type=>{
},

value=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Implementation) {

partitionInto(self_,destination,value.origin_span);

partitionInto(self_,destination,value.declaration);

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.contract);

partitionInto(self_,destination,value.head);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.parameter_names);

partitionInto(self_,destination,value.row_variables);

partitionInto(self_,destination,value.row_parameter_names);

partitionInto(self_,destination,value.row_parameters);

partitionInto(self_,destination,value.predicates);

partitionInto(self_,destination,value.members);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::ImplementationMember) {

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.root);

partitionInto(self_,destination,value.target);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::ImplementationMemberKind) {

match value {

type_=>{
},

value=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::ExternalTarget) {

partitionInto(self_,destination,value.unit);

partitionInto(self_,destination,value.binding);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::MemberTemplate) {

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.contract);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.arguments);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::SelectedProof) {

partitionInto(self_,destination,value.predicate_target);

partitionInto(self_,destination,value.context);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.predicate);

partitionInto(self_,destination,value.implementation);

partitionInto(self_,destination,value.contract);

partitionInto(self_,destination,value.arguments);

partitionInto(self_,destination,value.members);

partitionInto(self_,destination,value.prerequisites);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::SelectedProofKind) {

match value {

implementation=>{
},

predicate=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::SelectedUse) {

partitionInto(self_,destination,value.node);

partitionInto(self_,destination,value.proof);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::DictionarySelection) {

partitionInto(self_,destination,value.owner);

partitionInto(self_,destination,value.quantifier);

partitionInto(self_,destination,value.goal);

partitionInto(self_,destination,value.proof);

partitionInto(self_,destination,value.members);

partitionInto(self_,destination,value.contents);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::DictionaryProof) {

match value {

selected payload=>{
partitionInto(self_,destination,payload.value);
},

given payload=>{
partitionInto(self_,destination,payload.value);
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::DictionaryGiven) {

partitionInto(self_,destination,value.opening);

partitionInto(self_,destination,value.introduction);

partitionInto(self_,destination,value.quantifier);

partitionInto(self_,destination,value.goal);

partitionInto(self_,destination,value.arguments);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::DictionaryUse) {

partitionInto(self_,destination,value.node);

partitionInto(self_,destination,value.binding);

partitionInto(self_,destination,value.opening);

partitionInto(self_,destination,value.introduction);

partitionInto(self_,destination,value.quantifier);

partitionInto(self_,destination,value.goal);

partitionInto(self_,destination,value.member);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Primitive) {

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.op);

partitionInto(self_,destination,value.array_op);

partitionInto(self_,destination,value.arity);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::PrimitiveKind) {

match value {

scalar=>{
},

array=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_backend_collection_ops::Op) {

match value {

length=>{
},

get=>{
},

set=>{
},

fill=>{
},

generate=>{
},

append=>{
},

prepend=>{
},

identity=>{
},

convert=>{
},

cursor=>{
},

cursor_has=>{
},

cursor_value=>{
},

cursor_advance=>{
},

concat=>{
},

slice=>{
},

simd_load=>{
},

simd_store=>{
},

flatten=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::LoopInfo) {

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.first);

partitionInto(self_,destination,value.end);

partitionInto(self_,destination,value.pattern);

partitionInto(self_,destination,value.body);

partitionInto(self_,destination,value.carries);

partitionInto(self_,destination,value.can_exit);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::LoopKind) {

match value {

forever=>{
},

range=>{
},

array=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::LoopCarry) {

partitionInto(self_,destination,value.incoming);

partitionInto(self_,destination,value.iteration);

partitionInto(self_,destination,value.backedge);

partitionInto(self_,destination,value.outgoing);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::ResolverInfo) {

partitionInto(self_,destination,value.operation);

partitionInto(self_,destination,value.resolver);

partitionInto(self_,destination,value.arguments);

partitionInto(self_,destination,value.member);

partitionInto(self_,destination,value.method);

partitionInto(self_,destination,value.method_type);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::ResolverOperation) {

match value {

monad=>{
},

pure=>{
},

bind=>{
},

forward=>{
},

iterate=>{
},

run=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::OperationValue) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.arguments);

partitionInto(self_,destination,value.signature);

partitionInto(self_,destination,value.witness);

partitionInto(self_,destination,value.witness_result);

partitionInto(self_,destination,value.instance);

partitionInto(self_,destination,value.capability);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::HandleEffects) {

partitionInto(self_,destination,value.node);

partitionInto(self_,destination,value.first);

partitionInto(self_,destination,value.second);

partitionInto(self_,destination,value.extended);

partitionInto(self_,destination,value.residual);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Diagnostic) {

partitionInto(self_,destination,value.code);

partitionInto(self_,destination,value.span);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_core::Code) {

match value {

unchecked=>{
},

unsupported=>{
},

unresolved_binding=>{
},

invalid_call=>{
},

complexity=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Interface) {

partitionInto(self_,destination,value.has_rank_contracts);

partitionInto(self_,destination,value.has_usage_contracts);

partitionInto(self_,destination,value.has_numeric_proofs);

partitionInto(self_,destination,value.proof_contracts);

partitionInto(self_,destination,value.capability_contracts);

partitionInto(self_,destination,value.unit);

partitionInto(self_,destination,value.graph);

partitionInto(self_,destination,value.patterns);

partitionInto(self_,destination,value.bindings);

partitionInto(self_,destination,value.obligations);

partitionInto(self_,destination,value.obligation_spans);

partitionInto(self_,destination,value.nominals);

partitionInto(self_,destination,value.constructors);

partitionInto(self_,destination,value.effect_families);

partitionInto(self_,destination,value.effect_templates);

partitionInto(self_,destination,value.associated);

partitionInto(self_,destination,value.contracts);

partitionInto(self_,destination,value.contract_predicates);

partitionInto(self_,destination,value.contract_members);

partitionInto(self_,destination,value.implementations);

partitionInto(self_,destination,value.implementation_predicates);

partitionInto(self_,destination,value.implementation_members);

partitionInto(self_,destination,value.member_templates);

partitionInto(self_,destination,value.selected_proofs);

partitionInto(self_,destination,value.selected_members);

partitionInto(self_,destination,value.selected_edges);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_frozen_types::Graph) {

partitionInto(self_,destination,value.nodes);

partitionInto(self_,destination,value.extra);

partitionInto(self_,destination,value.rows);

partitionInto(self_,destination,value.labels);

partitionInto(self_,destination,value.operations);

partitionInto(self_,destination,value.row_variable_count);

partitionInto(self_,destination,value.quantifier_goals);

partitionInto(self_,destination,value.quantifier_obligations);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_frozen_types::PatternGraph) {

partitionInto(self_,destination,value.nodes);

partitionInto(self_,destination,value.extra);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_parameter_patterns::Node) {

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.a);

partitionInto(self_,destination,value.b);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_check_parameter_patterns::Kind) {

match value {

binding=>{
},

tuple=>{
},

array=>{
},

record=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Binding) {

partitionInto(self_,destination,value.capability_flow);

partitionInto(self_,destination,value.capability_parameters);

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.named_function);

partitionInto(self_,destination,value.ty);

partitionInto(self_,destination,value.scheme);

partitionInto(self_,destination,value.external);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Nominal) {

partitionInto(self_,destination,value.affine);

partitionInto(self_,destination,value.has_usage);

partitionInto(self_,destination,value.closed_storage);

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.is_opaque);

partitionInto(self_,destination,value.storage);

partitionInto(self_,destination,value.declaration);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.patterns);

partitionInto(self_,destination,value.parameter_names);

partitionInto(self_,destination,value.constructors);

partitionInto(self_,destination,value.alias);

partitionInto(self_,destination,value.alias_rows);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Constructor) {

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.nominal);

partitionInto(self_,destination,value.tag);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.scheme);

partitionInto(self_,destination,value.payload);

partitionInto(self_,destination,value.declared_record);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::EffectFamily) {

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.callable);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.patterns);

partitionInto(self_,destination,value.parameter_names);

partitionInto(self_,destination,value.operations);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::EffectTemplate) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.family);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.parameter);

partitionInto(self_,destination,value.result);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Associated) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.member);

partitionInto(self_,destination,value.operator);

partitionInto(self_,destination,value.binding);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_principal_interface::Contract) {

partitionInto(self_,destination,value.declaration);

partitionInto(self_,destination,value.private);

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.parameters);

partitionInto(self_,destination,value.variables);

partitionInto(self_,destination,value.patterns);

partitionInto(self_,destination,value.parameter_names);

partitionInto(self_,destination,value.row_variables);

partitionInto(self_,destination,value.row_parameter_names);

partitionInto(self_,destination,value.row_parameters);

partitionInto(self_,destination,value.predicates);

partitionInto(self_,destination,value.members);

partitionInto(self_,destination,value.requires_implementation);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::Module) {

partitionInto(self_,destination,value.identity);

partitionInto(self_,destination,value.imports);

partitionInto(self_,destination,value.implicit_prelude);

partitionInto(self_,destination,value.source_imports);

partitionInto(self_,destination,value.core);

partitionInto(self_,destination,value.interface);

partitionInto(self_,destination,value.exports);

partitionInto(self_,destination,value.fixities);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::Identity) {

partitionInto(self_,destination,value.normalized_path);

partitionInto(self_,destination,value.source_digest);

partitionInto(self_,destination,value.source_bytes);

partitionInto(self_,destination,value.prelude);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::ImportResolution) {

partitionInto(self_,destination,value.path);

partitionInto(self_,destination,value.target);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::Export) {

partitionInto(self_,destination,value.name);

partitionInto(self_,destination,value.target);

partitionInto(self_,destination,value.kind);

partitionInto(self_,destination,value.catalog);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::ExportKind) {

match value {

value=>{
},

nominal=>{
},

constructor=>{
},

effect_family=>{
},

contract=>{
},

implementation=>{
},

}

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::Fixity) {

partitionInto(self_,destination,value.operator);

partitionInto(self_,destination,value.target);

partitionInto(self_,destination,value.precedence);

partitionInto(self_,destination,value.association);

partitionInto(self_,destination,value.named);

partitionInto(self_,destination,value.producer);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::FrozenDependency) {

partitionInto(self_,destination,value.symbols);

partitionInto(self_,destination,value.modules);

}

fn partitionInto(self_:Owner&,destination:Owner&,value:blot_reuse_frozen_dependency::Symbol) {

partitionInto(self_,destination,value.text);

}

// Retained readers share immutable runs; every mutation requires the sole lease.
fn unique(self_:const Owner&)->bool {return valid(self_)&&leases[self_.lease-1].references==1;}
fn retain(self_:Owner)->Owner,Error {if !valid(self_) {return Owner{..},blot_error::Error.invalid_artifact;}let at=self_.lease-1;if leases[at].references==0xffffffffffffffff {return Owner{..},blot_error::Error.dependency_limit;}leases[at].references+=1;return self_,blot_error::Error.none;}
fn release(self_:Owner&) {self_.deinit();}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_header_module:blot_check_core::Module[>..]=[];
fn allocate(self_:Owner&,sample:blot_check_core::Module,length:i64)->blot_check_core::Module[:],Error {assert(unique(self_));if length<0 {return default<blot_check_core::Module[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_check_core::Module[:]>(),blot_error::Error.none;}let run=pool_header_module.alloc_slice(length);let error=remember(self_,Run.run_header_module{run, ..});if error!=blot_error::Error.none {pool_header_module.free_slice(run);return default<blot_check_core::Module[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const blot_check_core::Module[:])->blot_check_core::Module[:] {assert(unique(self_));if values.len==0 {return default<blot_check_core::Module[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_header_module run=>{if blot_support::same_slice_identity(run.values,values) {return pool_header_module.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_header_path:HeaderPath[>..]=[];
fn allocate(self_:Owner&,sample:HeaderPath,length:i64)->HeaderPath[:],Error {assert(unique(self_));if length<0 {return default<HeaderPath[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<HeaderPath[:]>(),blot_error::Error.none;}let run=pool_header_path.alloc_slice(length);let error=remember(self_,Run.run_header_path{run, ..});if error!=blot_error::Error.none {pool_header_path.free_slice(run);return default<HeaderPath[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const HeaderPath[:])->HeaderPath[:] {assert(unique(self_));if values.len==0 {return default<HeaderPath[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_header_path run=>{if blot_support::same_slice_identity(run.values,values) {return pool_header_path.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_header_digest:HeaderDigest[>..]=[];
fn allocate(self_:Owner&,sample:HeaderDigest,length:i64)->HeaderDigest[:],Error {assert(unique(self_));if length<0 {return default<HeaderDigest[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<HeaderDigest[:]>(),blot_error::Error.none;}let run=pool_header_digest.alloc_slice(length);let error=remember(self_,Run.run_header_digest{run, ..});if error!=blot_error::Error.none {pool_header_digest.free_slice(run);return default<HeaderDigest[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const HeaderDigest[:])->HeaderDigest[:] {assert(unique(self_));if values.len==0 {return default<HeaderDigest[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_header_digest run=>{if blot_support::same_slice_identity(run.values,values) {return pool_header_digest.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_header_name:blot_backend_runtime_identity::Name[>..]=[];
fn allocate(self_:Owner&,sample:blot_backend_runtime_identity::Name,length:i64)->blot_backend_runtime_identity::Name[:],Error {assert(unique(self_));if length<0 {return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.none;}let run=pool_header_name.alloc_slice(length);let error=remember(self_,Run.run_header_name{run, ..});if error!=blot_error::Error.none {pool_header_name.free_slice(run);return default<blot_backend_runtime_identity::Name[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const blot_backend_runtime_identity::Name[:])->blot_backend_runtime_identity::Name[:] {assert(unique(self_));if values.len==0 {return default<blot_backend_runtime_identity::Name[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_header_name run=>{if blot_support::same_slice_identity(run.values,values) {return pool_header_name.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_header_import:blot_reuse_entry_frontend_cutoff::Import[>..]=[];
fn allocate(self_:Owner&,sample:blot_reuse_entry_frontend_cutoff::Import,length:i64)->blot_reuse_entry_frontend_cutoff::Import[:],Error {assert(unique(self_));if length<0 {return default<blot_reuse_entry_frontend_cutoff::Import[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<blot_reuse_entry_frontend_cutoff::Import[:]>(),blot_error::Error.none;}let run=pool_header_import.alloc_slice(length);let error=remember(self_,Run.run_header_import{run, ..});if error!=blot_error::Error.none {pool_header_import.free_slice(run);return default<blot_reuse_entry_frontend_cutoff::Import[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const blot_reuse_entry_frontend_cutoff::Import[:])->blot_reuse_entry_frontend_cutoff::Import[:] {assert(unique(self_));if values.len==0 {return default<blot_reuse_entry_frontend_cutoff::Import[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_header_import run=>{if blot_support::same_slice_identity(run.values,values) {return pool_header_import.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_header_owner:Owner[>..]=[];
fn allocate(self_:Owner&,sample:Owner,length:i64)->Owner[:],Error {assert(unique(self_));if length<0 {return default<Owner[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<Owner[:]>(),blot_error::Error.none;}let run=pool_header_owner.alloc_slice(length);let error=remember(self_,Run.run_header_owner{run, ..});if error!=blot_error::Error.none {pool_header_owner.free_slice(run);return default<Owner[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const Owner[:])->Owner[:] {assert(unique(self_));if values.len==0 {return default<Owner[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_header_owner run=>{if blot_support::same_slice_identity(run.values,values) {return pool_header_owner.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}

// Header runs retain their own slots; child payloads use explicit reader pins.
reusable[] var pool_bool:bool[>..]=[];
fn allocate(self_:Owner&,sample:bool,length:i64)->bool[:],Error {assert(unique(self_));if length<0 {return default<bool[:]>(),blot_error::Error.invalid_artifact;}if length==0 {return default<bool[:]>(),blot_error::Error.none;}let run=pool_bool.alloc_slice(length);let error=remember(self_,Run.run_bool{run, ..});if error!=blot_error::Error.none {pool_bool.free_slice(run);return default<bool[:]>(),error;}return run,blot_error::Error.none;}
fn mutable(self_:const Owner&,values:const bool[:])->bool[:] {assert(unique(self_));if values.len==0 {return default<bool[:]>();}var next=leases[self_.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_bool run=>{if blot_support::same_slice_identity(run.values,values) {return pool_bool.realloc_slice(run.values,run.values.len);}},_=>{}}}abort("private header view must name this unique journal");}
