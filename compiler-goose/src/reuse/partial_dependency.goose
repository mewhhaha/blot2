// Mix admitted dependency interfaces with newly loaded ordinary source.
// Every escaping Core catalog and nested payload has an explicit retained owner.
namespace blot_reuse_partial_dependency;
import dictionary;
import reuse.project;
import reuse.project_check;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_payload;
import reuse.dependency_consumer;
import reuse.dependency_closure;
import reuse.body_check_cache;
import reuse.entry_frontend_cutoff;
import reuse.frontend_binding_relocation;
import reuse.frontend_reference_relocation;
import reuse.retained_dependency;
import reuse.source_completion;
import reuse.purity_diagnostics;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import check.core;
import check.check;
import check.core_builder;
import check.parallel_lowering;
import check.diagnostic_location;
import backend.core_backend;
import backend.runtime_identity;
import backend.array_cost_explanation;
import parse.ast;
import parse.syntax_diagnostics;
import support.blake3;
import support.error;
import support.option;
type Error=blot_error::Error;
type Core=blot_check_core::Module;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type Project=blot_reuse_project::Project;
type CheckedProject=blot_reuse_project_check::CheckedProject;
type Cache=blot_reuse_body_check_cache::Cache;
type Owner=blot_reuse_dependency_payload::Owner;
type OwnedCore=blot_reuse_dependency_payload::Owned<Core>;
type OwnedFrozen=blot_reuse_dependency_payload::Owned<Frozen>;
type ConsumerResult=blot_reuse_dependency_consumer::Result;
type ConsumerDiagnostic=blot_reuse_dependency_consumer::Diagnostic;
type Stats=blot_reuse_dependency_consumer::Stats;
type Import=blot_reuse_entry_frontend_cutoff::Import;
type Origin=blot_check_diagnostic_location::Origin;
type CompileOptions=blot_backend_core_backend::CompileOptions;
type Workspace=blot_backend_core_backend::CompileWorkspace;
reusable[] var result_bytes:u8[>..]=[];
reusable[] var result_origins:Origin[>..]=[];
reusable[] var core_owners:Owner[>..]=[];
fn copyResultBytes(bytes:const u8[:])->u8[:] {let result=result_bytes.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn releaseResultBytes(bytes:u8[:]) {if bytes.len!=0 {result_bytes.free_slice(bytes);}}
struct Result {
 array_costs:blot_support::Option<blot_backend_array_cost_explanation::Snapshot> =blot_support::none<blot_backend_array_cost_explanation::Snapshot>(),
 result:ConsumerResult=default<ConsumerResult>(),diagnostic_filename:blot_support::Option<u8[:]> =blot_support::none<u8[:]>(),related_filename:blot_support::Option<u8[:]> =blot_support::none<u8[:]>(),
 origins:blot_check_diagnostic_location::OwnedOrigins=blot_check_diagnostic_location::OwnedOrigins{},source_bytes:i64=0,fresh_modules:i64=0,cached_modules:i64=0,portable:bool=false,
}
fn deinit(self_:Result&) {
 self_.result.deinit();if self_.array_costs.present {self_.array_costs.value.deinit();}
 if self_.diagnostic_filename.present {releaseResultBytes(self_.diagnostic_filename.value);}if self_.related_filename.present {releaseResultBytes(self_.related_filename.value);}
 for origin in self_.origins.entries {if origin.filename.len!=0 {result_bytes.free_slice(origin.filename);}}
 if self_.origins.entries.len!=0 {result_origins.free_slice(self_.origins.entries);}self_=Result{};
}
// catalog_owner pins the vector itself, paths, ordinals, digests and all identity
// byte/name runs. unit_owners pins each Core's nested tables independently.
struct Prepared {
 source_completion:blot_reuse_source_completion::Entry?=null,source_digests:u8[32][:]=default<u8[32][:]>(),body_caches:Cache[:]=default<Cache[:]>(),units:Core[:]=default<Core[:]>(),
 identity:blot_backend_runtime_identity::Metadata=blot_backend_runtime_identity::Metadata{},unit_order:u32[:]=default<u32[:]>(),paths:const u8[:][:]=default<const u8[:][:]>(),cached:i64=0,borrowed:bool[:]=default<bool[:]>(),entry_imports:Import[:]=default<Import[:]>(),entry_implicit_prelude:bool=false,
 entry:u32=0,prelude:u32=0,source_mode:bool=false,source_bytes:i64=0,stats:Stats=default<Stats>(),catalog_owner:Owner=Owner{},unit_owners:Owner[:]=default<Owner[:]>(),seed_pin:blot_reuse_retained_dependency::InputPin=blot_reuse_retained_dependency::InputPin{},
}
fn isBorrowed(self_:const Prepared&,index:i64)->bool {if self_.borrowed.len!=0 {return self_.borrowed[index];}return index<self_.cached;}
fn cachedCount(self_:const Prepared&)->i64 {if self_.borrowed.len==0 {return self_.cached;}var count:i64=0;for borrowed in self_.borrowed {if borrowed {count++;}}return count;}
fn inheritBodyCaches(self_:Prepared&,caches:const Cache[:],paths:const u8[:][:])->Error {return copyBodyCacheOffers(self_.body_caches,self_.paths,blot_support::none<const blot_support::Option<blot_reuse_project_check::Module>[:]>(),caches,paths);}
fn attachSeedPin(self_:Prepared&,pin:blot_reuse_retained_dependency::InputPin&)->Error {
 if !self_.catalog_owner.unique() || self_.seed_pin.owners().len!=0 || pin.owners().len==0 {return blot_error::Error.invalid_artifact;}
 self_.seed_pin=pin;pin=blot_reuse_retained_dependency::InputPin{};return blot_error::Error.none;
}
fn deinit(self_:Prepared&) {
 let receipt .= self_.source_completion;if receipt {receipt.deinit();}self_.source_completion .=null;
 blot_reuse_project_check::releaseBodyCaches(self_.body_caches);
 for &owner in self_.unit_owners {owner.release();}if self_.unit_owners.len!=0 {core_owners.free_slice(self_.unit_owners);}
 self_.seed_pin.deinit();self_.catalog_owner.release();self_=Prepared{};
}
fn takeCore(self_:Prepared&,index:i64)->OwnedCore,Error {
 if index<0 || index>=self_.units.len || self_.isBorrowed(index) || !self_.catalog_owner.unique() || self_.unit_owners[index].lease==0 {return default<OwnedCore>(),blot_error::Error.invalid_artifact;}
 let receipt .= self_.source_completion;if receipt {receipt.deinit();}self_.source_completion .=null;
 let value=OwnedCore{self_.units[index],self_.unit_owners[index]};self_.unit_owners[index]=Owner{};let unit=value.value.unit;self_.units[index]=default<Core>();self_.units[index].unit=unit;return value,blot_error::Error.none;
}
fn rebindFrozenPrefix(self_:Prepared&,seed:const Frozen&)->Error {
 let names=self_.identity.view();
 if !self_.catalog_owner.unique() || self_.source_mode || self_.units.len==0 || self_.units.len>0xffffffff || self_.entry!=self_.units.len || seed.modules.len!=self_.units.len-1 || self_.paths.len!=self_.units.len || names.owners.len!=self_.units.len || names.symbols.len!=seed.symbols.len || seed.symbols.len==0 {return blot_error::Error.invalid_artifact;}
 if self_.borrowed.len!=0 && self_.borrowed.len!=self_.units.len {return blot_error::Error.invalid_artifact;}if self_.isBorrowed(self_.entry-1) {return blot_error::Error.invalid_artifact;}
 for symbol,id in seed.symbols {if id==0 {if symbol.text.len!=0 {return blot_error::Error.invalid_artifact;}}else {let name=names.symbol(id as u32);if !name.present || name.value!=symbol.text {return blot_error::Error.invalid_artifact;}}}
 for module,index in seed.modules {let id=(index+1) as u32;let owner=names.owner(id);if module.core.unit!=id || module.interface.unit!=id || self_.units[index].unit!=id || module.core.diagnostics.len!=0 || self_.paths[index]!=module.identity.normalized_path || !owner.present || owner.value!=module.identity.normalized_path {return blot_error::Error.invalid_artifact;}}
 // Without a seed capability, copy the new prefix before publishing anything.
 // An attached pin permits the exact immutable descriptor identity required by
 // source-completion receipts; ordinary raw-Frozen callers receive owned copies.
 var copies:OwnedCore[>..<]=[];
 if self_.seed_pin.owners().len==0 {for module in seed.modules {let copy,error=blot_reuse_dependency_payload::clone(module.core);if error!=blot_error::Error.none {let __cleanup_result_1_0: Error = error; {for &copy in copies {copy.deinit();}} return __cleanup_result_1_0;}copies.push(copy);}}
 let receipt .= self_.source_completion;if receipt {receipt.deinit();}self_.source_completion .=null;
 for module,index in seed.modules {self_.unit_owners[index].release();if self_.seed_pin.owners().len!=0 {self_.units[index]=module.core;}else {self_.units[index]=copies[index].value;self_.unit_owners[index]=copies[index].owner;copies[index].owner=Owner{};}if self_.borrowed.len!=0 {self_.borrowed[index]=true;}}
 self_.cached=seed.modules.len;let __cleanup_result_2_0: Error = blot_error::Error.none; {for &copy in copies {copy.deinit();}} return __cleanup_result_2_0;
 {for &copy in copies {copy.deinit();}} }
fn emit(self_:const Prepared&,workspace:Workspace&)->Result,Error {return self_.emitWithOptions(workspace,CompileOptions{..});}
fn emitWithOptions(self_:const Prepared&,workspace:Workspace&,options:CompileOptions)->Result,Error {
 var actual=options;actual.source_completion.entry .=self_.source_completion;actual.identity=blot_support::some(self_.identity.view());actual.diagnostic_source_digests=self_.source_digests;actual.unit_order=self_.unit_order;actual.diagnostic_prelude_unit=self_.prelude;actual.diagnostic_source_mode=self_.source_mode;
 let staged=blot_backend_core_backend::pinWorkspaceInputs(workspace,self_.units,self_.catalog_owner,self_.unit_owners,self_.seed_pin.owners());if staged!=blot_error::Error.none {return Result{},staged;}
 let compiled,error=blot_backend_core_backend::compileWithOptions(workspace,self_.units,self_.entry,actual);if error!=blot_error::Error.none {return Result{},error;}
 var output=Result{result:ConsumerResult{compiled:compiled,stats:self_.stats},source_bytes:self_.source_bytes,fresh_modules:self_.units.len-self_.cachedCount(),cached_modules:self_.cachedCount()};var published=false;
 let pinned=blot_backend_core_backend::pinResult(output.result.compiled,self_.catalog_owner,self_.unit_owners,self_.seed_pin.owners());if pinned!=blot_error::Error.none {let __cleanup_result_3_0: Result = Result{}; let __cleanup_result_3_1: Error = pinned; {if !published {output.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;}
 if options.explain_allocations {let costs,error=blot_backend_array_cost_explanation::analyze(self_.units,self_.paths,self_.entry,self_.prelude);if error!=blot_error::Error.none {let __cleanup_result_4_0: Result = Result{}; let __cleanup_result_4_1: Error = error; {if !published {output.deinit();}} return __cleanup_result_4_0, __cleanup_result_4_1;}output.array_costs=blot_support::some(costs);}
 if compiled.diagnostic.present {
  let issue=compiled.diagnostic.value;if issue.unit==0 || issue.unit>self_.paths.len {let __cleanup_result_5_0: Result = Result{}; let __cleanup_result_5_1: Error = blot_error::Error.invalid_unit; {if !published {output.deinit();}} return __cleanup_result_5_0, __cleanup_result_5_1;}output.diagnostic_filename=blot_support::some(copyResultBytes(self_.paths[issue.unit-1]));
  let origins=result_origins.alloc_slice(issue.origins.items().len);for &origin in origins {origin=default<Origin>();}output.origins.entries=origins;
  for origin,index in issue.origins.items() {let unit=origin.location.unit;if unit==0 || unit>self_.paths.len {let __cleanup_result_6_0: Result = Result{}; let __cleanup_result_6_1: Error = blot_error::Error.invalid_unit; {if !published {output.deinit();}} return __cleanup_result_6_0, __cleanup_result_6_1;}let path=copyResultBytes(self_.paths[unit-1]);origins[index]=blot_check_diagnostic_location::init(origin.kind,path,origin.location.span);}
  if issue.related.present {let location=issue.related.value;if location.unit==0 || location.unit>self_.paths.len {let __cleanup_result_7_0: Result = Result{}; let __cleanup_result_7_1: Error = blot_error::Error.invalid_unit; {if !published {output.deinit();}} return __cleanup_result_7_0, __cleanup_result_7_1;}output.related_filename=blot_support::some(copyResultBytes(self_.paths[location.unit-1]));}
 }
 published=true;let __cleanup_result_8_0: Result = output; let __cleanup_result_8_1: Error = blot_error::Error.none; {if !published {output.deinit();}} return __cleanup_result_8_0, __cleanup_result_8_1;
 {if !published {output.deinit();}} }
enum Preparation {inactive,ready{value:Prepared},rejected{value:Result}}
fn deinit(self_:Preparation&) {match self_ {inactive=>{},ready payload=>{payload.value.deinit();},rejected payload=>{payload.value.deinit();}}self_=Preparation.inactive;}
fn reject(source:const Project&,entry_path:const u8[:],diagnostic:ConsumerDiagnostic)->Preparation,Error {
 var path=entry_path;if diagnostic.unit!=0 {path=source.filename(diagnostic.unit);}let cached=min(source.units.len,source.compiledCount());
 return Preparation.rejected{Result{result:ConsumerResult{compiled:default<blot_backend_core_backend::Result>(),stats:Stats{},diagnostic:blot_support::some(diagnostic)},diagnostic_filename:blot_support::some(copyResultBytes(path)),source_bytes:source.source_bytes,fresh_modules:source.units.len-cached,cached_modules:cached}},blot_error::Error.none;
}
struct OrderFrame {unit:u32,next:i64=0}
fn sourceOrder(source:const Project&,owner:Owner&)->u32[:],Error {
 var states:u8[>..<]=[];states.resize(source.units.len,0);var stack:OrderFrame[>..<]=[];var order:u32[>..<]=[];
 for root in [source.prelude_unit,source.entry] {
  if root==0 {continue;}if root>states.len {return default<u32[:]>(),blot_error::Error.invalid_unit;}if states[root-1]==2 {continue;}states[root-1]=1;stack.push(OrderFrame{root});
  while stack.len!=0 {
   let position=stack.len-1;let frame=stack[position];let unit .= source.unit(frame.unit);var implicit:i64=0;if unit.implicit_prelude {implicit=1;}let imports=source.unitImports(frame.unit);
   if frame.next==implicit+imports.len {states[frame.unit-1]=2;order.push(frame.unit);stack.pop();continue;}
   stack[position].next++;var target=source.prelude_unit;if frame.next>=implicit {target=imports[frame.next-implicit].target;}
   if target==0 || target>states.len || states[target-1]==1 {return default<u32[:]>(),blot_error::Error.invalid_unit;}if states[target-1]==2 {continue;}states[target-1]=1;stack.push(OrderFrame{target});
  }
 }
 if order.len!=states.len {return default<u32[:]>(),blot_error::Error.dependency_set_changed;}return owner.copy(order[..]);
}
fn prepare<E>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&)->Preparation,Error {
 let loaded,error=blot_reuse_project::loadCompiled(entry_path,options,dependency);if error!=blot_error::Error.none {return Preparation.inactive,error;}var source=loaded;let __cleanup_result_9_0, __cleanup_result_9_1 = prepareProject(executor,source,entry_path,output_identity,dependency.value); {source.deinit();} return __cleanup_result_9_0, __cleanup_result_9_1;
 {source.deinit();} }
fn prepareReadOnly<E,P>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:const Frozen&,inputs:P&)->Preparation,Error {return prepareReadOnlyMode(executor,entry_path,output_identity,options,dependency,inputs,blot_support::none<EntryPrevious>(),false);}
fn prepareReadOnly<E>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:const Frozen&)->Preparation,Error {var inputs=blot_reuse_project::FileInputs{};return prepareReadOnly(executor,entry_path,output_identity,options,dependency,inputs);}
fn prepareReadOnlyWithBodies<E,P>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:const Frozen&,inputs:P&,previous:blot_support::Option<EntryPrevious>)->Preparation,Error {return prepareReadOnlyMode(executor,entry_path,output_identity,options,dependency,inputs,previous,true);}
fn prepareReadOnlyMode<E,P>(executor:E&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:const Frozen&,inputs:P&,previous:blot_support::Option<EntryPrevious>,retain_bodies:bool)->Preparation,Error {
 let loaded,error=blot_reuse_project::loadCompiledReadOnly(entry_path,options,dependency,inputs);if error!=blot_error::Error.none {return Preparation.inactive,error;}var source=loaded;
 if source.units.len!=dependency.modules.len+1 {let __cleanup_result_10_0: Preparation = Preparation.inactive; let __cleanup_result_10_1: Error = blot_error::Error.dependency_set_changed; {source.deinit();} return __cleanup_result_10_0, __cleanup_result_10_1;}let __cleanup_result_11_0, __cleanup_result_11_1 = prepareProjectMode(executor,source,entry_path,output_identity,dependency,null,previous,retain_bodies,blot_support::none<CheckedProject>()); {source.deinit();} return __cleanup_result_11_0, __cleanup_result_11_1;
 {source.deinit();} }
fn prepareProject<E>(executor:E&,source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&)->Preparation,Error {return prepareProjectMode(executor,source,entry_path,output_identity,dependency,null,blot_support::none<EntryPrevious>(),false,blot_support::none<CheckedProject>());}
fn prepareProjectKeepingCheck<E>(executor:E&,source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&,kept:blot_support::Option<CheckedProject>&)->Preparation,Error {assert(!kept.present);return prepareProjectMode(executor,source,entry_path,output_identity,dependency,kept,blot_support::none<EntryPrevious>(),true,blot_support::none<CheckedProject>());}
struct EntryPrevious {prepared:const Prepared?=null,source:const u8[:]=default<const u8[:]>(),reuse_modules:bool=false,body_only:bool=false}
fn prepareProjectKeepingEntry<E>(executor:E&,source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&,kept:blot_support::Option<CheckedProject>&,previous:blot_support::Option<EntryPrevious>)->Preparation,Error {assert(!kept.present);return prepareProjectMode(executor,source,entry_path,output_identity,dependency,kept,previous,true,blot_support::none<CheckedProject>());}
fn prepareProjectWithCheck<E>(executor:E&,source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&,checked:CheckedProject,kept:blot_support::Option<CheckedProject>&,previous:blot_support::Option<EntryPrevious>)->Preparation,Error {assert(!kept.present && !checked.deferred_entry.present);return prepareProjectMode(executor,source,entry_path,output_identity,dependency,kept,previous,true,blot_support::some(checked));}
fn checkPrevious(old:EntryPrevious)->blot_reuse_entry_frontend_cutoff::Previous {
 let prepared .= old.prepared;assert(prepared!=null && prepared.entry!=0 && prepared.entry<=prepared.units.len);
           let __field_order_541_entry: u32 = prepared.entry; let __field_order_542_prelude: u32 = prepared.prelude; let __field_order_543_implicit_prelude: bool = prepared.entry_implicit_prelude; let __field_order_544_names: blot_backend_runtime_identity::View = prepared.identity.view(); let __field_order_545_source: const u8[:] = old.source; let __field_order_546_imports: const blot_reuse_entry_frontend_cutoff::Import[:] = prepared.entry_imports; let __field_order_547_reuse_modules: bool = old.reuse_modules; let __field_order_548_reuse_entry: bool = !old.body_only; let __field_order_549_bodies: const blot_reuse_body_check_cache::Cache[:] = prepared.body_caches; let __field_order_550_entry_core: const blot_check_core::Module? .= prepared.units[prepared.entry-1]; return blot_reuse_entry_frontend_cutoff::Previous{ reuse_entry: __field_order_548_reuse_entry, bodies: __field_order_549_bodies, reuse_modules: __field_order_547_reuse_modules, entry_core: __field_order_550_entry_core, entry: __field_order_541_entry, prelude: __field_order_542_prelude, implicit_prelude: __field_order_543_implicit_prelude, names: __field_order_544_names, source: __field_order_545_source, imports: __field_order_546_imports };
}
fn prepareProjectMode<E>(executor:E&,source:Project&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,dependency:const Frozen&,kept:blot_support::Option<CheckedProject>?,previous:blot_support::Option<EntryPrevious>,retain_bodies:bool,precomputed:blot_support::Option<CheckedProject>)->Preparation,Error {
 var owned_check=precomputed;
 if source.compiled_modules.len!=dependency.modules.len {let __cleanup_result_12_0: Preparation = Preparation.inactive; let __cleanup_result_12_1: Error = blot_error::Error.invalid_artifact; {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_12_0, __cleanup_result_12_1;}
 if source.diagnostics.len!=0 {
  let issue=source.diagnostics.items[0];
  if issue.publication.present {
   let unit .= source.unit(issue.unit);var diagnostic:ConsumerDiagnostic;
   if issue.parse_code.present {let value,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"parse-project",unit.source,issue.publication.value,unit.tree.diagnostics.items);if error!=blot_error::Error.none {let __cleanup_result_13_0: Preparation = Preparation.inactive; let __cleanup_result_13_1: Error = error; {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_13_0, __cleanup_result_13_1;}diagnostic=value;}
   else {let value,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"parse-project",unit.source,issue.publication.value,issue.lexical_details);if error!=blot_error::Error.none {let __cleanup_result_14_0: Preparation = Preparation.inactive; let __cleanup_result_14_1: Error = error; {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_14_0, __cleanup_result_14_1;}diagnostic=value;}
   let __cleanup_result_15_0, __cleanup_result_15_1 = reject(source,entry_path,diagnostic); {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_15_0, __cleanup_result_15_1;
  }
  let diagnostic,error=blot_reuse_dependency_consumer::init(issue.unit,"load",issue.codeName(),issue.span,issue.message());if error!=blot_error::Error.none {let __cleanup_result_16_0: Preparation = Preparation.inactive; let __cleanup_result_16_1: Error = error; {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_16_0, __cleanup_result_16_1;}let __cleanup_result_17_0, __cleanup_result_17_1 = reject(source,entry_path,diagnostic); {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_17_0, __cleanup_result_17_1;
 }
 if output_identity.present {for unit in source.units.items {if output_identity.value==source.symbols.get(unit.filename) {let __cleanup_result_18_0: Preparation = Preparation.inactive; let __cleanup_result_18_1: Error = blot_error::Error.output_is_source; {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_18_0, __cleanup_result_18_1;}}}
 var checked:CheckedProject;
 if owned_check.present {checked=owned_check.value;owned_check=blot_support::none<CheckedProject>();}
 else {
  var offered=blot_support::none<blot_reuse_entry_frontend_cutoff::Previous>();if previous.present {offered=blot_support::some(checkPrevious(previous.value));}
  let value,error=blot_reuse_project_check::checkProjectToFirstDiagnostic(executor,source,offered,previous.present || retain_bodies);if error!=blot_error::Error.none {let __cleanup_result_19_0: Preparation = Preparation.inactive; let __cleanup_result_19_1: Error = error; {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_19_0, __cleanup_result_19_1;}checked=value;
 }
 var check_transferred=false;
 if checked.diagnostics.len!=0 {
  let portable,error=portableRejection(source,checked.diagnostics[0]);if error!=blot_error::Error.none {let __cleanup_result_20_0: Preparation = Preparation.inactive; let __cleanup_result_20_1: Error = error; {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_20_0, __cleanup_result_20_1;}
  let value,error=rejectChecked(source,entry_path,checked.diagnostics[0]);if error!=blot_error::Error.none {let __cleanup_result_21_0: Preparation = Preparation.inactive; let __cleanup_result_21_1: Error = error; {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_21_0, __cleanup_result_21_1;}var rejection=value;match rejection {rejected payload=>{payload.value.portable=portable;},_=>{abort("rejection factory returned no diagnostic");}}let __cleanup_result_22_0: Preparation = rejection; let __cleanup_result_22_1: Error = blot_error::Error.none; {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_22_0, __cleanup_result_22_1;
 }
 let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {let __cleanup_result_23_0: Preparation = Preparation.inactive; let __cleanup_result_23_1: Error = error; {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_23_0, __cleanup_result_23_1;}
 var ready=Prepared{ cached:dependency.modules.len, entry:source.entry, prelude:source.prelude_unit, source_mode:source.input_mode==blot_reuse_project::InputMode.source, source_bytes:source.source_bytes, stats:Stats{body_elaborations:checked.body_elaborations,imported_schemes:checked.imported_schemes,normalization:checked.normalization}, catalog_owner:owner };
 var transferred=false;
 let count=source.units.len;
 let units,error=blot_reuse_dependency_payload::alloc<Core>(ready.catalog_owner,count);if error!=blot_error::Error.none {let __cleanup_result_24_0: Preparation = Preparation.inactive; let __cleanup_result_24_1: Error = error; {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_24_0, __cleanup_result_24_1;}ready.units=units;for &unit in ready.units {unit=default<Core>();}
 ready.unit_owners=core_owners.alloc_slice(count);for &owner in ready.unit_owners {owner=Owner{};}
 let borrowed,error=blot_reuse_dependency_payload::alloc<bool>(ready.catalog_owner,count);if error!=blot_error::Error.none {let __cleanup_result_25_0: Preparation = Preparation.inactive; let __cleanup_result_25_1: Error = error; {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_25_0, __cleanup_result_25_1;}ready.borrowed=borrowed;for &borrowed in ready.borrowed {borrowed=false;}
 let paths,error=blot_reuse_dependency_payload::alloc<const u8[:]>(ready.catalog_owner,count);if error!=blot_error::Error.none {let __cleanup_result_26_0: Preparation = Preparation.inactive; let __cleanup_result_26_1: Error = error; {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_26_0, __cleanup_result_26_1;}ready.paths=paths;for &path in ready.paths {path=[];}
 var slots:blot_check_parallel_lowering::Slot[>..<]=[];let batch,error=lowerFresh(executor,source,checked,slots);if error!=blot_error::Error.none {let __cleanup_result_27_0: Preparation = Preparation.inactive; let __cleanup_result_27_1: Error = error; {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_27_0, __cleanup_result_27_1;}var lowered=batch;
 for unit,index in source.units.items {
  let id=(index+1) as u32;let path,error=ready.catalog_owner.copy(source.filename(id));if error!=blot_error::Error.none {let __cleanup_result_28_0: Preparation = Preparation.inactive; let __cleanup_result_28_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_28_0, __cleanup_result_28_1;}ready.paths[index]=path;
  let compiled .= checked.compiledModule(source,id);var ir:OwnedCore;
  if compiled {
   // Raw Frozen input carries no lifetime authority. Deep-copy its Core even
   // when its semantic ordinal remains a cached/borrowed seed position.
   let copied,error=blot_reuse_dependency_payload::clone(compiled.core);if error!=blot_error::Error.none {let __cleanup_result_29_0: Preparation = Preparation.inactive; let __cleanup_result_29_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_29_0, __cleanup_result_29_1;}ir=copied;
   if id<=source.compiled_modules.len {let original:const blot_reuse_frozen_dependency::Module& =source.compiled_modules[index];if compiled .== original {ready.borrowed[index]=true;}}
  }else if id==source.entry && checked.entry_cutoff.reused!=0 {
   assert(previous.present);let old .= previous.value.prepared;assert(old!=null);let copied,error=blot_reuse_dependency_payload::clone(old.units[index]);if error!=blot_error::Error.none {let __cleanup_result_30_0: Preparation = Preparation.inactive; let __cleanup_result_30_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_30_0, __cleanup_result_30_1;}ir=copied;
   let targets=blot_reuse_frontend_binding_relocation::Targets{units:checked.binding_maps};if targets.changes() {let error=blot_reuse_frontend_reference_relocation::rewrite(ir.owner,ir.value,targets);if error!=blot_error::Error.none {ir.deinit();let __cleanup_result_31_0: Preparation = Preparation.inactive; let __cleanup_result_31_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_31_0, __cleanup_result_31_1;}}
  }else {
   if lowered.present {let copied,error=lowered.value.take(index);if error!=blot_error::Error.none {let __cleanup_result_32_0: Preparation = Preparation.inactive; let __cleanup_result_32_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_32_0, __cleanup_result_32_1;}ir=copied;}
   else {let copied,error=blot_check_core_builder::lowerWithOrigins(unit.tree,source.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(source));if error!=blot_error::Error.none {let __cleanup_result_33_0: Preparation = Preparation.inactive; let __cleanup_result_33_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_33_0, __cleanup_result_33_1;}ir=copied;}
   ir.value.unit=id;ready.stats.body_lowerings+=ir.value.body_lowerings;
  }
  ready.units[index]=ir.value;ready.unit_owners[index]=ir.owner;
  if source.compiledModule(id)==null {ready.stats.syntax_nodes+=unit.tree.nodes.len-1;}
  if ir.value.diagnostics.len!=0 {let issue=ir.value.diagnostics[0];let diagnostic,error=blot_reuse_dependency_consumer::init(id,"lower",coreCodeName(issue.code),issue.span,issue.message());if error!=blot_error::Error.none {let __cleanup_result_34_0: Preparation = Preparation.inactive; let __cleanup_result_34_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_34_0, __cleanup_result_34_1;}let __cleanup_result_35_0, __cleanup_result_35_1 = reject(source,entry_path,diagnostic); {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_35_0, __cleanup_result_35_1;}
 }
 let digests,error=blot_reuse_dependency_payload::alloc<u8[32]>(ready.catalog_owner,count);if error!=blot_error::Error.none {let __cleanup_result_36_0: Preparation = Preparation.inactive; let __cleanup_result_36_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_36_0, __cleanup_result_36_1;}ready.source_digests=digests;
 var identity_owners:blot_backend_runtime_identity::Owner[>..<]=[];
 for index in count {let id=(index+1) as u32;let compiled .= source.compiledModule(id);if compiled {digests[index]=compiled.identity.source_digest;}else {digests[index]=blot_support_blake3::hash(source.unit(id).source);}identity_owners.push(blot_backend_runtime_identity::Owner{id,ready.paths[index]});}
 let order,error=sourceOrder(source,ready.catalog_owner);if error!=blot_error::Error.none {let __cleanup_result_37_0: Preparation = Preparation.inactive; let __cleanup_result_37_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_37_0, __cleanup_result_37_1;}ready.unit_order=order;
 let captured,error=blot_backend_runtime_identity::capture(source.symbols,identity_owners[..],count);if error!=blot_error::Error.none {let __cleanup_result_38_0: Preparation = Preparation.inactive; let __cleanup_result_38_1: Error = error; {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_38_0, __cleanup_result_38_1;}var identity=captured;
 let bytes,error=ready.catalog_owner.copy(identity.bytes);if error!=blot_error::Error.none {let __cleanup_result_39_0: Preparation = Preparation.inactive; let __cleanup_result_39_1: Error = error; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_39_0, __cleanup_result_39_1;}ready.identity.bytes=bytes;
 let symbols,error=ready.catalog_owner.copy(identity.symbols);if error!=blot_error::Error.none {let __cleanup_result_40_0: Preparation = Preparation.inactive; let __cleanup_result_40_1: Error = error; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_40_0, __cleanup_result_40_1;}ready.identity.symbols=symbols;
 let owners,error=ready.catalog_owner.copy(identity.owners);if error!=blot_error::Error.none {let __cleanup_result_41_0: Preparation = Preparation.inactive; let __cleanup_result_41_1: Error = error; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_41_0, __cleanup_result_41_1;}ready.identity.owners=owners;
 let imports=source.unitImports(source.entry);let owned_imports,error=blot_reuse_dependency_payload::alloc<Import>(ready.catalog_owner,imports.len);if error!=blot_error::Error.none {let __cleanup_result_42_0: Preparation = Preparation.inactive; let __cleanup_result_42_1: Error = error; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_42_0, __cleanup_result_42_1;}ready.entry_imports=owned_imports;
 for from,index in imports {owned_imports[index]=Import{from.path,from.target};}ready.entry_implicit_prelude=source.unit(source.entry).implicit_prelude;
 let caches,error=blot_reuse_project_check::takeBodyCaches(checked);if error!=blot_error::Error.none {let __cleanup_result_43_0: Preparation = Preparation.inactive; let __cleanup_result_43_1: Error = error; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_43_0, __cleanup_result_43_1;}ready.body_caches=caches;
 if previous.present {let old .= previous.value.prepared;assert(old!=null);let error=copyBodyCacheOffers(ready.body_caches,ready.paths,blot_support::some(checked.modules),old.body_caches,old.paths);if error!=blot_error::Error.none {let __cleanup_result_44_0: Preparation = Preparation.inactive; let __cleanup_result_44_1: Error = error; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_44_0, __cleanup_result_44_1;}}
 if kept {kept=blot_support::some(checked);check_transferred=true;}transferred=true;let __cleanup_result_45_0: Preparation = Preparation.ready{ready}; let __cleanup_result_45_1: Error = blot_error::Error.none; {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} return __cleanup_result_45_0, __cleanup_result_45_1;
 {identity.deinit();} {if lowered.present {lowered.value.deinit();}} {if !transferred {ready.deinit();}} {if !check_transferred {checked.deinit();}} {if owned_check.present {owned_check.value.deinit();}} }
fn coreCodeName(code:blot_check_core::Code)->const u8[:] {match code {const for <N,V> in variants<blot_check_core::Code> {V=>{return N;},}}}
fn portableRejection(source:const Project&,issue:blot_reuse_project_check::Diagnostic)->bool,Error {
 if source.input_mode!=blot_reuse_project::InputMode.project || issue.unit==0 || issue.unit>source.units.len || source.compiledModule(issue.unit)!=null {return false,blot_error::Error.none;}
 if issue.hole.present || issue.explanation.present || issue.context_len!=0 || issue.numeric_literal.present || issue.purity.present || issue.detail.present || issue.source.present {return false,blot_error::Error.none;}
 match issue.code {
  semantic=>{if !issue.semantic.present {return false,blot_error::Error.none;}match issue.semantic.value {
   task_budget,proof_analysis_limit,capability_analysis_limit,associated_limit,nesting_limit,inference_budget,usage_analysis_limit,staging_budget=>{return false,blot_error::Error.none;},_=>{}}},
  duplicate_name,unknown_export,entry_module,declaration_modifier=>{},
  resolution_budget,source_validation,dependency_failed=>{return false,blot_error::Error.none;},
 }
 var seen:bool[>..<]=[];seen.resize(source.units.len,false);var stack:u32[>..<]=[];for root in [source.entry,source.prelude_unit] {if root!=0 {stack.push(root);}}
 while stack.len!=0 {let unit=stack.pop();if unit==0 || unit>seen.len {return false,blot_error::Error.none;}if seen[unit-1] {continue;}seen[unit-1]=true;if source.unit(unit).implicit_prelude && source.prelude_unit!=0 {stack.push(source.prelude_unit);}for edge in source.unitImports(unit) {stack.push(edge.target);}}
 for reached in seen {if !reached {return false,blot_error::Error.none;}}return true,blot_error::Error.none;
}
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
  var message:u8[>..<]=[];let error=blot_reuse_purity_diagnostics::format(source.symbols,"",witness,message);if error!=blot_error::Error.none {return Preparation.inactive,error;}var actual=publication;actual.message=message[..];let details=[witness];
  let diagnostic,error=blot_reuse_dependency_consumer::publishedDiagnostic(issue.unit,"check-project",unit.source,actual,details[..]);if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);
 }
 var message:u8[>..<]=[];message.append(issue.message());if issue.symbol!=0 {let code=issue.codeName();if code=="unknown_intrinsic" || code=="unknown_record_field" {message.append(" ");}else {message.append(": ");}message.append(source.symbols.get(issue.symbol));}
 let diagnostic,error=blot_reuse_dependency_consumer::init(issue.unit,"check-project",issue.codeName(),issue.span,message[..]);if error!=blot_error::Error.none {return Preparation.inactive,error;}return reject(source,entry_path,diagnostic);
}
fn lowerFresh<E>(executor:E&,source:Project&,checked:CheckedProject&,slots:blot_check_parallel_lowering::Slot[>..<]&)->blot_support::Option<blot_check_parallel_lowering::Batch<E>>,Error {
 if source.lowering.workers<=1 {return blot_support::none<blot_check_parallel_lowering::Batch<E>>(),blot_error::Error.none;}
 var inputs:blot_support::Option<blot_check_parallel_lowering::Input>[>..<]=[];
 for unit,index in source.units.items {let id=(index+1) as u32;var input=blot_support::none<blot_check_parallel_lowering::Input>();if checked.compiledModule(source,id)==null && !(id==source.entry && checked.entry_cutoff.reused!=0) {input=blot_support::some(blot_check_parallel_lowering::Input{tree:unit.tree,checked:checked.module(id).checked});}inputs.push(input);}
 return blot_check_parallel_lowering::run(executor,source.lowering.io,source.lowering.workers,source.symbols,blot_reuse_project_check::moduleOrigins(source),inputs[..],slots);
}
struct CacheOffer {unique:bool=true,cache:const Cache?=null}
fn copyBodyCacheOffers(destination:Cache[:],paths:const u8[:][:],checked:blot_support::Option<const blot_support::Option<blot_reuse_project_check::Module>[:]>,prior_caches:const Cache[:],prior_paths:const u8[:][:])->Error {
 if destination.len!=paths.len || prior_caches.len!=prior_paths.len {return blot_error::Error.none;}
 var offers:dictionary<const u8[:],CacheOffer> =dictionary<const u8[:],CacheOffer>{};
 for path,index in prior_paths {let existing .= offers.get(path);if existing {existing.unique=false;existing.cache .=null;}else {let cache:const Cache& =prior_caches[index];offers.insert(path,CacheOffer{cache:cache});}}
 for &cache,index in destination {if checked.present && checked.value[index].present {continue;}if cache.bodies.len!=0 {continue;}let offer .= offers.get(paths[index]);if !offer || !offer.unique {continue;}let prior .= offer.cache;if !prior {continue;}let copy,error=prior.clone();if error!=blot_error::Error.none {return error;}cache.deinit();cache=copy;}return blot_error::Error.none;
}
fn compileMode<E>(executor:E&,workspace:Workspace&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&,consume_interfaces:bool,backend_options:CompileOptions)->Result,Error {
 let preparation,error=prepare(executor,entry_path,output_identity,options,dependency);if error!=blot_error::Error.none {return Result{},error;}var owned=preparation;
 match owned {
  inactive=>{abort("inactive dependency preparation observed");},
  rejected payload=>{let result=payload.value;owned=Preparation.inactive;let __cleanup_result_46_0: Result = result; let __cleanup_result_46_1: Error = blot_error::Error.none; {owned.deinit();} return __cleanup_result_46_0, __cleanup_result_46_1;},
  ready payload=>{
   if consume_interfaces {
    if !dependency.owner.unique() {let __cleanup_result_47_0: Result = Result{}; let __cleanup_result_47_1: Error = blot_error::Error.invalid_artifact; {owned.deinit();} return __cleanup_result_47_0, __cleanup_result_47_1;}
    for &module in dependency.value.modules {let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {let __cleanup_result_48_0: Result = Result{}; let __cleanup_result_48_1: Error = error; {owned.deinit();} return __cleanup_result_48_0, __cleanup_result_48_1;}var discarded=owner;dependency.owner.partitionInto(discarded,module.interface);discarded.deinit();module.interface=default<blot_reuse_principal_interface::Interface>();}
   }
   let __cleanup_result_49_0, __cleanup_result_49_1 = payload.value.emitWithOptions(workspace,backend_options); {owned.deinit();} return __cleanup_result_49_0, __cleanup_result_49_1;
  },
 }
 {owned.deinit();} }
fn compile<E>(executor:E&,workspace:Workspace&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&)->Result,Error {return compileMode(executor,workspace,entry_path,output_identity,options,dependency,false,CompileOptions{..});}
fn compileOwned<E>(executor:E&,workspace:Workspace&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&)->Result,Error {return compileMode(executor,workspace,entry_path,output_identity,options,dependency,true,CompileOptions{..});}
fn compileOwnedWithOptions<E>(executor:E&,workspace:Workspace&,entry_path:const u8[:],output_identity:blot_support::Option<const u8[:]>,options:blot_reuse_project::Options,dependency:OwnedFrozen&,backend_options:CompileOptions)->Result,Error {return compileMode(executor,workspace,entry_path,output_identity,options,dependency,true,backend_options);}
