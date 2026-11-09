// Dependency-first semantic regions retain source trees and producer identities.
namespace blot_reuse_project_check;
import dictionary;
import reuse.project;
import reuse.principal_interface;
import reuse.frozen_dependency;
import reuse.dependency_payload;
import reuse.entry_frontend_cutoff;
import reuse.frontend_binding_relocation;
import reuse.frontend_reference_relocation;
import reuse.body_check_cache;
import reuse.completion_fit;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import check.check;
import check.core;
import parse.ast;
import parse.symbols;
import parse.source_operators;
import work_counters;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;
import support.path;
import support.blake3;
import check.frozen_types;
import .project_check_owners;
import .project_check_engine;
import .project_check_origins;
import .project_check_services;
import .project_check_module;
import .project_check_parallel;
import .project_check_factory;
type Error=blot_error::Error;
type Project=blot_reuse_project::Project;
type ExportKind=blot_reuse_frozen_dependency::ExportKind;
type ExternalTarget=blot_check_check::ExternalTarget;
type Span=blot_parse_ast::Span;
type Checked=blot_check_check::Checked;
type BindingMap=blot_reuse_frontend_binding_relocation::Map;
type FrozenModule=blot_reuse_frozen_dependency::Module;
struct EditorQuery {unit:u32,marker:blot_check_check::EditorMarker,budget:blot_reuse_completion_fit::Budget&}
struct Export {name:u32,target:ExternalTarget=ExternalTarget{0,0, ..},kind:ExportKind=blot_reuse_frozen_dependency::ExportKind.value,catalog:u32=0}
struct Module {checked:Checked,exports:Export[:],valid:bool}
enum Code {resolution_budget,source_validation,semantic,duplicate_name,unknown_export,entry_module,declaration_modifier,dependency_failed}
struct Diagnostic {
 unit:u32,span:Span,code:Code,semantic:blot_support::Option<blot_check_check::Code> =blot_support::none<blot_check_check::Code>(),
 type_application:blot_support::Option<blot_check_check::TypeApplication> =blot_support::none<blot_check_check::TypeApplication>(),symbol:u32=0,implicit_type_witness:bool=false,
 source_terminator:blot_parse_source_operators::Terminator=blot_parse_source_operators::terminator_none,
 numeric_literal:blot_support::Option<blot_parse_ast::NumericFault> =blot_support::none<blot_parse_ast::NumericFault>(),
 purity:blot_support::Option<blot_check_check::PurityWitness> =blot_support::none<blot_check_check::PurityWitness>(),detail:blot_support::Option<const u8[:]> =blot_support::none<const u8[:]>(),
 hole:blot_support::Option<blot_reuse_hole_diagnostics::Snapshot> =blot_support::none<blot_reuse_hole_diagnostics::Snapshot>(),explanation:blot_support::Option<blot_reuse_dispatch_explanation::Explanation> =blot_support::none<blot_reuse_dispatch_explanation::Explanation>(),
 contexts:blot_check_check::DiagnosticContext[2]=[blot_check_check::DiagnosticContext{blot_check_check::DiagnosticContextKind.callee,Span{0,0, ..}, ..},blot_check_check::DiagnosticContext{blot_check_check::DiagnosticContextKind.argument,Span{0,0, ..}, ..}],context_len:u8=0,
 source:blot_support::Option<blot_reuse_project::Diagnostic> =blot_support::none<blot_reuse_project::Diagnostic>(),
}
fn codeName(self_:Diagnostic)->const u8[:] {
 if self_.semantic.present {match self_.semantic.value {const for <N,V> in variants<blot_check_check::Code> {V=>{return N;},}}}
 if self_.source.present {return self_.source.value.codeName();}match self_.code {const for <N,V> in variants<Code> {V=>{return N;},}}
}
fn message(self_:Diagnostic)->const u8[:] {
 if self_.detail.present {return self_.detail.value;}if self_.semantic.present {return blot_check_check::Diagnostic{ code:self_.semantic.value, span:self_.span, node:0, type_application:self_.type_application, symbol:self_.symbol, implicit_type_witness:self_.implicit_type_witness, source_terminator:self_.source_terminator, .. }.message();}if self_.source.present {return self_.source.value.message();}
 match self_.code {
 resolution_budget=>{return "Module forwarding resolution budget exhausted";},source_validation=>{return "Source loading or parsing failed";},semantic=>{return "Module semantic checking failed";},
 duplicate_name=>{return "Import aliases cannot collide with another alias or a local declaration";},unknown_export=>{return "Imported module does not export this declaration";},
 entry_module=>{return "Only the entry module may declare host entries";},declaration_modifier=>{return "Unknown top-level declaration modifier";},dependency_failed=>{return "Imported module has no successful semantic interface";},
 }
}
struct Deferred {resolution_remaining:i64,associated_remaining:i64}
struct CheckedProject {
 owner:ResultOwner=ResultOwner{..},body_caches:blot_reuse_body_check_cache::Cache[:]=default<blot_reuse_body_check_cache::Cache[:]>(),modules:blot_support::Option<Module>[:]=default<blot_support::Option<Module>[:]>(),diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),
 body_elaborations:i64=0,imported_schemes:i64=0,normalization:blot_work_counters::Normalization=blot_work_counters::Normalization{..},
 entry_cutoff:blot_reuse_entry_frontend_cutoff::Stats=blot_reuse_entry_frontend_cutoff::Stats{..},module_cutoff:blot_reuse_entry_frontend_cutoff::Stats=blot_reuse_entry_frontend_cutoff::Stats{..},
 reused_modules:bool[:]=default<bool[:]>(),interface_colors:blot_reuse_entry_frontend_cutoff::Color[:]=default<blot_reuse_entry_frontend_cutoff::Color[:]>(),binding_maps:blot_support::Option<BindingMap>[:]=default<blot_support::Option<BindingMap>[:]>(),relocated_modules:blot_support::Option<FrozenModule>[:]=default<blot_support::Option<FrozenModule>[:]>(),
 deferred_entry:blot_support::Option<Deferred> =blot_support::none<Deferred>(),
}
fn compiledModule(self_:const CheckedProject&,source:const Project&,id:i64)->const FrozenModule? {
 let compiled .= source.compiledModule(id);if compiled {return compiled;}if id==0 || id>self_.reused_modules.len || !self_.reused_modules[id-1] {return null;}
 if id<=self_.relocated_modules.len && self_.relocated_modules[id-1].present {return self_.relocated_modules[id-1].value;}return source.compiled_modules[id-1];
}
fn module(self_:const CheckedProject&,unit:u32)->const Module& {assert(unit!=0 && unit<=self_.modules.len && self_.modules[unit-1].present);return self_.modules[unit-1].value;}
fn interface(self_:const CheckedProject&,target:ExternalTarget)->blot_check_check::SchemeInterface {
 let producer:const Checked& =self_.module(target.unit).checked;let binding=producer.bindings[target.binding];var summary=blot_support::none<blot_check_check::SchemeSummary>();          if binding.summary.shareable {summary=blot_support::some(binding.summary);}
           let __field_order_523_producer_binding: blot_check_check::BindingId = target.binding; let __field_order_524_proof_contract: const blot_check_numeric_proof_headers::Owned? .= blot_check_check::checkedProofContract(producer,target.binding); let __field_order_525_types: blot_check_frozen_types::Source = blot_check_frozen_types::fromStore(producer.types); let __field_order_526_scheme: blot_check_types::Scheme = binding.scheme; let __field_order_527_summary: blot_support::Option<blot_check_check::SchemeSummary> = summary; let __field_order_528_capability_flow: blot_check_check::CapabilityFlow = binding.capability_flow; let __field_order_529_capability_parameters: blot_check_capability_flow::Parameters = binding.capability_parameters; let __field_order_530_named_function: bool = binding.named_function; let __field_order_531_obligations: const blot_check_types::Obligation[:] = producer.obligations; let __field_order_532_callees: blot_check_check::Callees = blot_check_check::Callees.live{blot_check_check::liveCallees(producer),..}; return blot_check_check::SchemeInterface{ summary: __field_order_527_summary, producer_binding: __field_order_523_producer_binding, proof_contract: __field_order_524_proof_contract, capability_flow: __field_order_528_capability_flow, capability_parameters: __field_order_529_capability_parameters, named_function: __field_order_530_named_function, types: __field_order_525_types, scheme: __field_order_526_scheme, obligations: __field_order_531_obligations, callees: __field_order_532_callees, .. };
}
// Contexts never carry an erased function pointer or a local Engine reference.
// The live project checker pins every catalog inspected by this generation.
struct BodyNameContext {slot:u32=0,generation:u64=0}
fn borrow(self_:BodyNameContext)->const Engine? {if self_.slot==0 || self_.slot-1>=engines.len {return null;}let value:const Engine& =engines[self_.slot-1];if !value.live || value.generation!=self_.generation {return null;}return value;}
fn lookup(self_:BodyNameContext,target:ExternalTarget)->blot_support::Option<const u8[:]> {let value .= self_.borrow();if !value {return blot_support::none<const u8[:]>();}return value.originalBindingName(target);}
fn unitOrigin(self_:BodyNameContext,unit:u32)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self_.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalUnitOrigin(unit);}
fn closedRows(self_:BodyNameContext,target:ExternalTarget)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self_.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalBindingClosedRows(target);}
fn qualification(self_:BodyNameContext,unit:u32,span:Span)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self_.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalQualification(unit,span);}
fn capabilities(self_:BodyNameContext,target:ExternalTarget)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self_.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalBindingCapabilities(target);}
