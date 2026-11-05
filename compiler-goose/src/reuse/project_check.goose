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
struct Export {name:u32,target:ExternalTarget=ExternalTarget{0,0, ..},kind:ExportKind=ExportKind.value,catalog:u32=0}
struct Module {checked:Checked,exports:Export[:],valid:bool}
enum Code {resolution_budget,source_validation,semantic,duplicate_name,unknown_export,entry_module,declaration_modifier,dependency_failed}
struct Diagnostic {
 unit:u32,span:Span,code:Code,semantic:blot_support::Option<blot_check_check::Code>=blot_support::none<blot_check_check::Code>(),
 type_application:blot_support::Option<blot_check_check::TypeApplication>=blot_support::none<blot_check_check::TypeApplication>(),symbol:u32=0,implicit_type_witness:bool=false,
 source_terminator:blot_parse_source_operators::Terminator=blot_parse_source_operators::terminator_none,
 numeric_literal:blot_support::Option<blot_parse_ast::NumericFault>=blot_support::none<blot_parse_ast::NumericFault>(),
 purity:blot_support::Option<blot_check_check::PurityWitness>=blot_support::none<blot_check_check::PurityWitness>(),detail:blot_support::Option<const u8[:]>=blot_support::none<const u8[:]>(),
 hole:blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>(),explanation:blot_support::Option<blot_reuse_dispatch_explanation::Explanation>=blot_support::none<blot_reuse_dispatch_explanation::Explanation>(),
 contexts:blot_check_check::DiagnosticContext[2]=[blot_check_check::DiagnosticContext{blot_check_check::DiagnosticContextKind.callee,Span{0,0, ..}, ..},blot_check_check::DiagnosticContext{blot_check_check::DiagnosticContextKind.argument,Span{0,0, ..}, ..}],context_len:u8=0,
 source:blot_support::Option<blot_reuse_project::Diagnostic>=blot_support::none<blot_reuse_project::Diagnostic>(),
}
fn codeName(self:Diagnostic)->const u8[:] {
 if self.semantic.present {match self.semantic.value {const for <N,V> in variants<blot_check_check::Code> {V=>{return N;},}}}
 if self.source.present {return self.source.value.codeName();}match self.code {const for <N,V> in variants<Code> {V=>{return N;},}}
}
fn message(self:Diagnostic)->const u8[:] {
 if self.detail.present {return self.detail.value;}if self.semantic.present {return blot_check_check::Diagnostic{code:self.semantic.value,node:0,span:self.span,type_application:self.type_application,symbol:self.symbol,implicit_type_witness:self.implicit_type_witness,source_terminator:self.source_terminator, ..}.message();}if self.source.present {return self.source.value.message();}
 match self.code {
 Code.resolution_budget=>{return "Module forwarding resolution budget exhausted";},Code.source_validation=>{return "Source loading or parsing failed";},Code.semantic=>{return "Module semantic checking failed";},
 Code.duplicate_name=>{return "Import aliases cannot collide with another alias or a local declaration";},Code.unknown_export=>{return "Imported module does not export this declaration";},
 Code.entry_module=>{return "Only the entry module may declare host entries";},Code.declaration_modifier=>{return "Unknown top-level declaration modifier";},Code.dependency_failed=>{return "Imported module has no successful semantic interface";},
 }
}
struct Deferred {resolution_remaining:i64,associated_remaining:i64}
struct CheckedProject {
 owner:ResultOwner=ResultOwner{..},body_caches:blot_reuse_body_check_cache::Cache[:]=[],modules:blot_support::Option<Module>[:]=[],diagnostics:Diagnostic[:]=[],
 body_elaborations:i64=0,imported_schemes:i64=0,normalization:blot_work_counters::Normalization=blot_work_counters::Normalization{..},
 entry_cutoff:blot_reuse_entry_frontend_cutoff::Stats=blot_reuse_entry_frontend_cutoff::Stats{..},module_cutoff:blot_reuse_entry_frontend_cutoff::Stats=blot_reuse_entry_frontend_cutoff::Stats{..},
 reused_modules:bool[:]=[],interface_colors:blot_reuse_entry_frontend_cutoff::Color[:]=[],binding_maps:blot_support::Option<BindingMap>[:]=[],relocated_modules:blot_support::Option<FrozenModule>[:]=[],
 deferred_entry:blot_support::Option<Deferred>=blot_support::none<Deferred>(),
}
fn compiledModule(self:const CheckedProject&,source:const Project&,id:i64)->const FrozenModule? {
 let compiled .= source.compiledModule(id);if compiled {return compiled;}if id==0 || id>self.reused_modules.len || !self.reused_modules[id-1] {return null;}
 if id<=self.relocated_modules.len && self.relocated_modules[id-1].present {return self.relocated_modules[id-1].value;}return source.compiled_modules[id-1];
}
fn module(self:const CheckedProject&,unit:u32)->const Module& {assert(unit!=0 && unit<=self.modules.len && self.modules[unit-1].present);return self.modules[unit-1].value;}
fn interface(self:const CheckedProject&,target:ExternalTarget)->blot_check_check::SchemeInterface {
 let producer:const Checked&=self.module(target.unit).checked;let binding=producer.bindings[target.binding];var summary=blot_support::none<blot_check_check::SchemeSummary>();if binding.summary.shareable {summary=blot_support::some(binding.summary);}
 return blot_check_check::SchemeInterface{producer_binding:target.binding,proof_contract:blot_check_check::checkedProofContract(producer,target.binding),types:blot_check_frozen_types::Source.store{producer.types, ..},scheme:binding.scheme,summary:summary,capability_flow:binding.capability_flow,capability_parameters:binding.capability_parameters,named_function:binding.named_function,obligations:producer.obligations,callees:blot_check_check::Callees.live{producer, ..}, ..};
}
// Contexts never carry an erased function pointer or a local Engine reference.
// The live project checker pins every catalog inspected by this generation.
struct BodyNameContext {slot:u32=0,generation:u64=0}
fn borrow(self:BodyNameContext)->const Engine? {if self.slot==0 || self.slot-1>=engines.len {return null;}let value:const Engine&=engines[self.slot-1];if !value.live || value.generation!=self.generation {return null;}return value;}
fn lookup(self:BodyNameContext,target:ExternalTarget)->blot_support::Option<const u8[:]> {let value .= self.borrow();if !value {return blot_support::none<const u8[:]>();}return value.originalBindingName(target);}
fn unitOrigin(self:BodyNameContext,unit:u32)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalUnitOrigin(unit);}
fn closedRows(self:BodyNameContext,target:ExternalTarget)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalBindingClosedRows(target);}
fn qualification(self:BodyNameContext,unit:u32,span:Span)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalQualification(unit,span);}
fn capabilities(self:BodyNameContext,target:ExternalTarget)->blot_support::Option<blot_reuse_body_check_cache::Digest> {let value .= self.borrow();if !value {return blot_support::none<blot_reuse_body_check_cache::Digest>();}return value.originalBindingCapabilities(target);}
