// Combine admitted generic modules with newly loaded ordinary source modules.
// Cached syntax/solvers are never reconstructed; new modules use the same
// source loader, checker and Core lowering as an ordinary project.
namespace blot_reuse_partial_dependency;
import std;
import reuse.project;
import reuse.project_check;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_payload;
import reuse.dependency_owned_headers;
import reuse.dependency_consumer;
import reuse.purity_diagnostics;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import check.core;
import check.check;
import check.core_builder;
import check.wire_schema;
import parse.ast;
import parse.syntax_diagnostics;
import phase_profile;
import support.error;
import support.option;
import support.native;
import support.project_packet;
import .retained_project;
import .persistent_project;
type Error=blot_error::Error;
type Core=blot_check_core::Module;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type Project=blot_reuse_project::Project;
type CheckedProject=blot_reuse_project_check::CheckedProject;
type Owner=blot_reuse_dependency_payload::Owner;
type OwnedCore=blot_reuse_dependency_payload::Owned<Core>;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
type ConsumerResult=blot_reuse_dependency_consumer::Result;
type ConsumerDiagnostic=blot_reuse_dependency_consumer::Diagnostic;
type Stats=blot_reuse_dependency_consumer::Stats;
reusable[] var result_bytes:u8[>..]=[];
// A scalar revision shares the immutable tables and owns only a new node slice.
struct CoreOwners { tables:Owner=Owner{}, nodes:Owner=Owner{} }
reusable[] var core_owners:CoreOwners[>..]=[];
fn copyResultBytes(bytes:const u8[:])->u8[:] {let result=result_bytes.alloc_slice(bytes.len);if bytes.len!=0 {blot_native::copy_u8(result[0],bytes[0],bytes.len as u64);}return result;}
fn releaseResultBytes(bytes:u8[:]) {if bytes.len!=0 {result_bytes.free_slice(bytes);}}
struct Result {result:ConsumerResult=default<ConsumerResult>(),diagnostic_filename:blot_support::Option<u8[:]> =blot_support::none<u8[:]>(),source_bytes:i64=0,fresh_modules:i64=0,cached_modules:i64=0}
fn deinit(self_:Result&) {self_.result.deinit();if self_.diagnostic_filename.present {releaseResultBytes(self_.diagnostic_filename.value);}self_=Result{};}
// Source-free owned frontend result for one project build. catalog_owner owns
// the unit vector, the paths and the flags; unit_owners owns each Core. A
// cached Core is a copy of the admitted seed's (raw frozen input carries no
// lifetime authority in this port); `borrowed` marks those positions.
struct Prepared {units:Core[:]=default<Core[:]>(),paths:const u8[:][:]=default<const u8[:][:]>(),borrowed:bool[:]=default<bool[:]>(),entry:u32=0,source_bytes:i64=0,stats:Stats=default<Stats>(),catalog_owner:Owner=Owner{},unit_owners:CoreOwners[:]=default<CoreOwners[:]>(),wire_owner:blot_project_packet::Owner=default<blot_project_packet::Owner>()}
// Re-publish the owned runs without retaining the temporary header.
fn publishPrepared(value:Prepared)->Prepared {
 assert(value.catalog_owner.unique());
 let units=value.catalog_owner.mutable(value.units);let paths=value.catalog_owner.mutable(value.paths);let borrowed=value.catalog_owner.mutable(value.borrowed);
 let unit_owners=core_owners.realloc_slice(value.unit_owners,value.unit_owners.len);assert(blot_support::same_slice_identity(unit_owners,value.unit_owners));
 return Prepared{units:units,paths:paths,borrowed:borrowed,entry:value.entry,source_bytes:value.source_bytes,stats:value.stats,catalog_owner:value.catalog_owner,unit_owners:unit_owners,wire_owner:value.wire_owner};
}
fn deinit(self_:Prepared&) {
 for &owners in self_.unit_owners {owners.nodes.release();owners.tables.release();}if self_.unit_owners.len!=0 {core_owners.free_slice(self_.unit_owners);}
 if self_.wire_owner.slot!=0 {self_.wire_owner.deinit();}
 self_.catalog_owner.release();self_=Prepared{};
}
fn cachedCount(self_:const Prepared&)->i64 {var count:i64=0;for borrowed in self_.borrowed {if borrowed {count++;}}return count;}
// Borrows Prepared. Every returned byte and diagnostic filename belongs to
// the new result.
fn emit(self_:const Prepared&,build_inputs:i64 = -1)->Result,Error {
 let compiled,error=blot_reuse_dependency_consumer::compileUnits(self_.units,self_.entry,build_inputs);if error!=blot_error::Error.none {return Result{},error;}
 var result=Result{result:ConsumerResult{compiled:compiled,stats:self_.stats, ..},source_bytes:self_.source_bytes,fresh_modules:self_.units.len-self_.cachedCount(),cached_modules:self_.cachedCount()};
 if compiled.failed {let unit=compiled.diagnostic.unit;if unit==0 || unit>self_.paths.len {result.deinit();return Result{},blot_error::Error.invalid_unit;}result.diagnostic_filename=blot_support::some(copyResultBytes(self_.paths[unit-1]));}
 return result,blot_error::Error.none;
}
fn emitWithAnalysis(self_:const Prepared&,pinfo:const blot_check_wire_schema::ProgramInfo&,build_inputs:i64 = -1)->Result,Error {
 let compiled,error=blot_reuse_dependency_consumer::compileUnitsWithAnalysis(self_.units,self_.entry,pinfo,build_inputs);if error!=blot_error::Error.none {return Result{},error;}
 var result=Result{result:ConsumerResult{compiled:compiled,stats:self_.stats, ..},source_bytes:self_.source_bytes,fresh_modules:self_.units.len-self_.cachedCount(),cached_modules:self_.cachedCount()};
 if compiled.failed {let unit=compiled.diagnostic.unit;if unit==0 || unit>self_.paths.len {result.deinit();return Result{},blot_error::Error.invalid_unit;}result.diagnostic_filename=blot_support::some(copyResultBytes(self_.paths[unit-1]));}
 return result,blot_error::Error.none;
}
// Both cases own their fresh allocations. Match and move one case or destroy
// the union; the admitted seed's Core/PI owner is always retained by the caller.
enum Preparation {inactive,ready{value:Prepared},rejected{value:Result}}
fn deinit(self_:Preparation&) {match self_ {inactive=>{},ready payload=>{var value=payload.value;value.deinit();},rejected payload=>{var value=payload.value;value.deinit();}}self_=Preparation.inactive;}
fn diagnosticFilename(source:const Project&,entry:const u8[:],unit:u32)->const u8[:] {
 if unit!=0 {return source.filename(unit);}
 return entry;
}
fn diagnosticFilename(result:const Result&,entry:const u8[:])->const u8[:] {
 if result.diagnostic_filename.present {return result.diagnostic_filename.value;}
 return entry;
}
fn reject(source:const Project&,entry_path:const u8[:],diagnostic:ConsumerDiagnostic)->Preparation,Error {
 // Invalid loader settings can reject before any seed module is installed.
 // Count actual installed units rather than the borrowed seed's capacity.
 let path=diagnosticFilename(source,entry_path,diagnostic.unit);let cached=min(source.units.len,source.compiledCount());
 return Preparation.rejected{Result{result:ConsumerResult{stats:Stats{},diagnostic:blot_support::Option<blot_reuse_dependency_consumer::Diagnostic>{true,diagnostic}, ..},diagnostic_filename:blot_support::some(copyResultBytes(path)),source_bytes:source.source_bytes,fresh_modules:source.units.len-cached,cached_modules:cached}},blot_error::Error.none;
}
// Loads/checks/lowers fresh source against an admitted unchanged seed. All
// Project, source, syntax and solver owners are destroyed before returning.
// The caller must validate seed wire/compiler/settings/source/import identity.
fn prepare(entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&)->Preparation,Error {
 let loaded,error=blot_reuse_project::loadCompiled(entry_path,options,dependency);if error!=blot_error::Error.none {return Preparation.inactive,error;}var source=loaded;let value,failure=prepareProject(source,entry_path,output_identity,dependency.value);source.deinit();return value,failure;
}
// Consumes no Project storage. Passing an empty dependency prepares an
// entirely fresh checked Project. A rejection publishes only the first
// diagnostic.
fn prepareProject(source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&)->Preparation,Error {
 return prepareProjectMode(source,entry_path,output_identity,dependency,null);
}
fn prepareProjectMode(source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&,retained:Retained?)->Preparation,Error {
 if source.compiled_modules.len!=dependency.modules.len {return Preparation.inactive,blot_error::Error.invalid_artifact;}
 if source.diagnostics.len!=0 {
  let issue=source.diagnostics.items[0];
  if issue.publication.present {
   let unit .= source.unit(issue.unit);var diagnostic:ConsumerDiagnostic;
   if issue.parse_code.present {let value,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"parse-project",unit.source,issue.publication.value,unit.tree.diagnostics.items);if error!=blot_error::Error.none {return Preparation.inactive,error;}diagnostic=value;}
   else {let value,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"parse-project",unit.source,issue.publication.value,issue.lexical_details);if error!=blot_error::Error.none {return Preparation.inactive,error;}diagnostic=value;}
   return reject(source,entry_path,diagnostic);
  }
  let diagnostic,error=blot_reuse_dependency_consumer::init(issue.unit,"load",issue.codeName(),issue.span,issue.message());if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);
 }
 if output_identity.present {for unit in source.units.items {if output_identity.value==source.symbols.get(unit.filename) {return Preparation.inactive,blot_error::Error.output_is_source;}}}
 if source.checking.workers>1 && source.checking.io && source.units.len>=16 && source.compiled_modules.len==0 && source.input_mode==blot_reuse_project::InputMode.project {
  let prepared,error=preparePersistent(source,retained);
  if error==blot_error::Error.out_of_memory {return Preparation.inactive,error;}
  match prepared {ready=>{return prepared,blot_error::Error.none;},_=>{}}
 }
 // Checking stops at the first module that reports a diagnostic.
 let parsed_symbols=source.symbols.entries.len;
 var debits=default<ModuleDebit[:]>();
 var checked=CheckedProject{..};
 var error=blot_error::Error.none;
 if retained!=null {
  debits=blot_reuse_project_check::allocateModuleDebits(source.units.len);
  var serial=source;
  serial.checking.workers=1;
  checked,error=blot_reuse_project_check::checkProjectToFirstDiagnosticTracked(serial,debits);
 } else {
  checked,error=blot_reuse_project_check::checkProjectToFirstDiagnosticWithWorkers(source);
 }
 if error!=blot_error::Error.none {blot_reuse_project_check::releaseModuleDebits(debits);return Preparation.inactive,error;}
 let value,failure=prepareChecked(source,entry_path,checked);
 if retained {
  match value {
   ready payload=>{retained.adopt(source,checked,parsed_symbols,debits);debits=default<ModuleDebit[:]>();},
   _=>{},
  }
 }
 blot_reuse_project_check::releaseModuleDebits(debits);
 checked.deinit();return value,failure;
}
fn prepareChecked(source:Project&,entry_path:const u8[:],checked:CheckedProject&)->Preparation,Error {
 if checked.diagnostics.len!=0 {return rejectChecked(source,entry_path,checked.diagnostics[0]);}
 let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return Preparation.inactive,error;}
 var ready=Prepared{entry:source.entry,source_bytes:source.source_bytes,stats:Stats{body_elaborations:checked.body_elaborations,imported_schemes:checked.imported_schemes,normalization:checked.normalization},catalog_owner:owner};
 let issue,failure=lowerUnits(source,checked,ready);if failure!=blot_error::Error.none {ready.deinit();return Preparation.inactive,failure;}
 if issue.present {ready.deinit();return reject(source,entry_path,issue.value);}
 return Preparation.ready{publishPrepared(ready)},blot_error::Error.none;
}
// Fills `ready` in unit order. A lowering diagnostic stops at its unit.
fn lowerUnits(source:Project&,checked:CheckedProject&,ready:Prepared&)->blot_support::Option<ConsumerDiagnostic>,Error {
 let count=source.units.len;
 let error=allocateCatalog(ready,count);if error!=blot_error::Error.none {return blot_support::none<ConsumerDiagnostic>(),error;}
 for unit,index in source.units.items {
  let id=(index+1) as u32;let path,error=ready.catalog_owner.copy(source.filename(id));if error!=blot_error::Error.none {return blot_support::none<ConsumerDiagnostic>(),error;}ready.paths[index]=path;
  let compiled .= source.compiledModule(id);var ir:OwnedCore;
  if compiled {
   let copied,error=blot_reuse_dependency_payload::clone(compiled.core);if error!=blot_error::Error.none {return blot_support::none<ConsumerDiagnostic>(),error;}ir=copied;ready.borrowed[index]=true;
  }else {
   let timing=blot_phase_profile::enter(blot_phase_profile::Phase.lower);let copied,error=blot_check_core_builder::lowerWithOrigins(unit.tree,source.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(source),true);timing.exit();if error!=blot_error::Error.none {return blot_support::none<ConsumerDiagnostic>(),error;}ir=copied;
   ir.value.unit=id;ready.stats.body_lowerings+=ir.value.body_lowerings;ready.stats.syntax_nodes+=unit.tree.nodes.len-1;
  }
  ready.units[index]=blot_reuse_dependency_owned_headers::canonical(ir.owner,ir.value);ready.unit_owners[index].tables=ir.owner;
  if ir.value.diagnostics.len!=0 {let issue=ir.value.diagnostics[0];let diagnostic,error=blot_reuse_dependency_consumer::init(id,"lower",coreCodeName(issue.code),issue.span,issue.message());if error!=blot_error::Error.none {return blot_support::none<ConsumerDiagnostic>(),error;}return blot_support::some(diagnostic),blot_error::Error.none;}
 }
 return blot_support::none<ConsumerDiagnostic>(),blot_error::Error.none;
}
fn allocateCatalog(ready:Prepared&,count:i64)->Error {
 let units,error=blot_reuse_dependency_payload::alloc<Core>(ready.catalog_owner,count);if error!=blot_error::Error.none {return error;}ready.units=units;for &unit in ready.units {unit=default<Core>();}
 ready.unit_owners=core_owners.alloc_slice(count);for &owner in ready.unit_owners {owner=CoreOwners{};}
 let borrowed,error=blot_reuse_dependency_payload::alloc<bool>(ready.catalog_owner,count);if error!=blot_error::Error.none {return error;}ready.borrowed=borrowed;for &flag in ready.borrowed {flag=false;}
 let paths,error=blot_reuse_dependency_payload::alloc<const u8[:]>(ready.catalog_owner,count);if error!=blot_error::Error.none {return error;}ready.paths=paths;for &path in ready.paths {path=default<const u8[:]>();}
 return blot_error::Error.none;
}
fn coreCodeName(code:blot_check_core::Code)->const u8[:] {match code {const for <N,V> in variants<blot_check_core::Code> {V=>{return N;},}}}
struct HoleDetails {hole:blot_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetails {explanation:blot_reuse_dispatch_explanation::Explanation,contexts:const blot_check_check::DiagnosticContext[:]}
struct ContextDetails {contexts:const blot_check_check::DiagnosticContext[:]}
fn rejectChecked(source:Project&,entry_path:const u8[:],issue:blot_reuse_project_check::Diagnostic)->Preparation,Error {
 let unit .= source.unit(issue.unit);let contexts=issue.contexts[..issue.context_len];let publication=blot_parse_syntax_diagnostics::Publication{cause:blot_parse_syntax_diagnostics::native_detail,code:issue.codeName(),span:issue.span,message:issue.message()};
 if issue.hole.present {let diagnostic,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"check-project",unit.source,publication,HoleDetails{issue.hole.value});if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);}
 if issue.explanation.present {let diagnostic,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"check-project",unit.source,publication,ExplanationDetails{issue.explanation.value,contexts});if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);}
 if contexts.len!=0 {let diagnostic,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"check-project",unit.source,publication,ContextDetails{contexts});if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);}
 if issue.numeric_literal.present {var actual=publication;actual.has_actual_token=true;actual.actual_token=issue.numeric_literal.value.actual_token;let details=[issue.numeric_literal.value];let diagnostic,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"check-project",unit.source,actual,details[..]);if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);}
 if issue.purity.present {
  let witness=issue.purity.value;if !witness.operation_name.present && !witness.foreign {return Preparation.inactive,blot_error::Error.operation_purity_origin_required;}
  var message:u8[>..]=[];let error=blot_reuse_purity_diagnostics::format(source.symbols,"",witness,message);if error!=blot_error::Error.none {return Preparation.inactive,error;}var actual=publication;actual.message=message[..];let details=[witness];
  let diagnostic,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"check-project",unit.source,actual,details[..]);if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);
 }
 var message:u8[>..<]=[];message.append(issue.message());if issue.symbol!=0 {let code=issue.codeName();if code=="unknown_intrinsic" || code=="unknown_record_field" {message.append(" ");}else {message.append(": ");}message.append(source.symbols.get(issue.symbol));}
 let diagnostic,error=blot_reuse_dependency_consumer::init(issue.unit,"check-project",issue.codeName(),issue.span,message[..]);if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);
}
// Dependency owner is borrowed throughout. All new frontend/solver owners are
// destroyed before code generation and all fresh Core is freed afterward.
fn compileMode(entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&,consume_interfaces:bool)->Result,Error {
 let preparation,error=prepare(entry_path,output_identity,options,dependency);if error!=blot_error::Error.none {return Result{},error;}var owned=preparation;
 match owned {
  inactive=>{abort("inactive dependency preparation observed");},
  rejected payload=>{let result=payload.value;owned=Preparation.inactive;return result,blot_error::Error.none;},
  ready payload=>{
   if consume_interfaces {
    if !dependency.owner.unique() {owned.deinit();return Result{},blot_error::Error.invalid_artifact;}
    for &module in dependency.value.modules {let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {owned.deinit();return Result{},error;}var discarded=owner;dependency.owner.partitionInto(discarded,module.interface);discarded.deinit();module.interface=default<blot_reuse_principal_interface::Interface>();}
   }
   let result,failure=payload.value.emit();owned.deinit();return result,failure;
  },
 }
}
// Borrowing compilation preserves every admitted principal interface.
fn compile(entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&)->Result,Error {return compileMode(entry_path,output_identity,options,dependency,false);}
// Successful fresh lowering ends the dependency principal-interface lifetime
// before code generation. The bundle can then only be destroyed, not reused
// or encoded. Frontend rejection leaves all seed interfaces intact.
fn compileOwned(entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&)->Result,Error {return compileMode(entry_path,output_identity,options,dependency,true);}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_partial_dependency::HoleDetails)->bool {return true;}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_partial_dependency::ExplanationDetails)->bool {return true;}

fn blot_reuse_dependency_consumer::forwardedDetails(details:blot_reuse_partial_dependency::ContextDetails)->bool {return true;}
