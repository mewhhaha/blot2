// Dependency-first semantic regions retain source trees and producer identities.
namespace squid_reuse_project_check;
import dictionary;
import reuse.project;
import reuse.principal_interface;
import reuse.frozen_dependency;
import reuse.dependency_payload;
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
import .project_check_workers;
import .persistent_unit;
type Error=squid_error::Error;
type Project=squid_reuse_project::Project;
type ExportKind=squid_reuse_frozen_dependency::ExportKind;
type ExternalTarget=squid_check_check::ExternalTarget;
type Span=squid_parse_ast::Span;
type Checked=squid_check_check::Checked;
type FrozenModule=squid_reuse_frozen_dependency::Module;
struct EditorQuery {unit:u32,marker:squid_check_check::EditorMarker,budget:squid_reuse_completion_fit::Budget&}
struct Export {name:u32,target:ExternalTarget=ExternalTarget{0,0, ..},kind:ExportKind=squid_reuse_frozen_dependency::ExportKind.value,catalog:u32=0}
struct Module {checked:Checked,exports:Export[:],valid:bool}
enum Code {resolution_budget,source_validation,semantic,duplicate_name,unknown_export,entry_module,declaration_modifier,dependency_failed}
struct Diagnostic {
 unit:u32,span:Span,code:Code,semantic:squid_support::Option<squid_check_check::Code> =squid_support::none<squid_check_check::Code>(),
 type_application:squid_support::Option<squid_check_check::TypeApplication> =squid_support::none<squid_check_check::TypeApplication>(),symbol:u32=0,implicit_type_witness:bool=false,
 source_terminator:squid_parse_source_operators::Terminator=squid_parse_source_operators::terminator_none,
 numeric_literal:squid_support::Option<squid_parse_ast::NumericFault> =squid_support::none<squid_parse_ast::NumericFault>(),
 purity:squid_support::Option<squid_check_check::PurityWitness> =squid_support::none<squid_check_check::PurityWitness>(),detail:squid_support::Option<const u8[:]> =squid_support::none<const u8[:]>(),
 hole:squid_support::Option<squid_reuse_hole_diagnostics::Snapshot> =squid_support::none<squid_reuse_hole_diagnostics::Snapshot>(),explanation:squid_support::Option<squid_reuse_dispatch_explanation::Explanation> =squid_support::none<squid_reuse_dispatch_explanation::Explanation>(),
 contexts:squid_check_check::DiagnosticContext[2]=[squid_check_check::DiagnosticContext{squid_check_check::DiagnosticContextKind.callee,Span{0,0, ..}, ..},squid_check_check::DiagnosticContext{squid_check_check::DiagnosticContextKind.argument,Span{0,0, ..}, ..}],context_len:u8=0,
 source:squid_support::Option<squid_reuse_project::Diagnostic> =squid_support::none<squid_reuse_project::Diagnostic>(),
}
fn codeName(self_:Diagnostic)->const u8[:] {
 if self_.semantic.present {match self_.semantic.value {const for <N,V> in variants<squid_check_check::Code> {V=>{return N;},}}}
 if self_.source.present {return self_.source.value.codeName();}match self_.code {const for <N,V> in variants<Code> {V=>{return N;},}}
}
fn message(self_:Diagnostic)->const u8[:] {
 if self_.detail.present {return self_.detail.value;}if self_.semantic.present {return squid_check_check::Diagnostic{ code:self_.semantic.value, span:self_.span, node:0, type_application:self_.type_application, symbol:self_.symbol, implicit_type_witness:self_.implicit_type_witness, source_terminator:self_.source_terminator, .. }.message();}if self_.source.present {return self_.source.value.message();}
 match self_.code {
 resolution_budget=>{return "Module forwarding resolution budget exhausted";},source_validation=>{return "Source loading or parsing failed";},semantic=>{return "Module semantic checking failed";},
 duplicate_name=>{return "Import aliases cannot collide with another alias or a local declaration";},unknown_export=>{return "Imported module does not export this declaration";},
 entry_module=>{return "Only the entry module may declare host entries";},declaration_modifier=>{return "Unknown top-level declaration modifier";},dependency_failed=>{return "Imported module has no successful semantic interface";},
 }
}
struct CheckedProject {
 owner:ResultOwner=ResultOwner{..},modules:squid_support::Option<Module>[:]=default<squid_support::Option<Module>[:]>(),diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),
 body_elaborations:i64=0,imported_schemes:i64=0,normalization:squid_work_counters::Normalization=squid_work_counters::Normalization{..},
}
fn module(self_:const CheckedProject&,unit:u32)->const Module& {assert(unit!=0 && unit<=self_.modules.len && self_.modules[unit-1].present);return self_.modules[unit-1].value;}
fn interface(self_:const CheckedProject&,target:ExternalTarget)->squid_check_check::SchemeInterface {
 return checkedInterface(self_.module(target.unit).checked,target);
}
fn checkedInterface(producer:const Checked&,target:ExternalTarget)->squid_check_check::SchemeInterface {
 let binding=producer.bindings[target.binding];var summary=squid_support::none<squid_check_check::SchemeSummary>();          if binding.summary.shareable {summary=squid_support::some(binding.summary);}
           let __field_order_523_producer_binding: squid_check_check::BindingId = target.binding; let __field_order_525_types: squid_check_frozen_types::Source = squid_check_frozen_types::fromStore(producer.types); let __field_order_526_scheme: squid_check_types::Scheme = binding.scheme; let __field_order_527_summary: squid_support::Option<squid_check_check::SchemeSummary> = summary; let __field_order_529_capability_parameters: squid_check_capability_flow::Parameters = binding.capability_parameters; let __field_order_530_named_function: bool = binding.named_function; let __field_order_531_obligations: const squid_check_types::Obligation[:] = producer.obligations; let __field_order_532_callees: squid_check_check::Callees = squid_check_check::Callees.live{squid_check_check::liveCallees(producer),..}; return squid_check_check::SchemeInterface{ summary: __field_order_527_summary, producer_binding: __field_order_523_producer_binding, capability_parameters: __field_order_529_capability_parameters, named_function: __field_order_530_named_function, types: __field_order_525_types, scheme: __field_order_526_scheme, obligations: __field_order_531_obligations, callees: __field_order_532_callees, .. };
}
// These callbacks borrow the invocation-local checker only during synchronous checking/capture.
struct BodyNameContext {engine:const Engine?=null}
fn borrow(self_:BodyNameContext)->const Engine? {return self_.engine;}
