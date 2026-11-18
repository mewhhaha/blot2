// One live checker context supplies typed producer services during inference.
namespace blot_reuse_project_check;
import .project_check;
import inference_limits;
import phase_profile;
struct SourceModule {validation:blot_check_check::SourceValidation,exports:Export[:],valid:bool}
struct CompiledCatalog {exports:Export[:]=default<Export[:]>(),declarations:blot_check_check::SourceDeclaration[:]=default<blot_check_check::SourceDeclaration[:]>()}
enum CatalogOwner {inactive,typed{value:const Checked&},source{value:const blot_check_check::SourceValidation&},frozen{value:const blot_reuse_principal_interface::Interface&}}
struct CatalogModule {owner:CatalogOwner=CatalogOwner.inactive,exports:const Export[:]=default<const Export[:]>(),valid:bool=false,summaries:const blot_check_check::SchemeSummary[:]=default<const blot_check_check::SchemeSummary[:]>()}
fn catalog(self_:CatalogModule)->blot_check_check::DeclarationCatalog {match self_.owner {
 typed payload=>{return blot_check_check::declarationCatalog(payload.value);},source payload=>{return blot_check_check::declarationCatalog(payload.value);},
 frozen payload=>{return blot_check_check::ImportedCatalog{frozen:blot_support::Option<blot_check_check::FrozenProducer>{true,blot_check_check::frozenProducer(payload.value,self_.summaries)},kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..}.catalog();},inactive=>{abort("inactive project declaration catalog");},
}}
fn declaration(self_:CatalogModule,binding:u32)->blot_check_check::SourceDeclaration {match self_.owner {
 typed payload=>{return blot_check_check::sourceDeclaration(payload.value.bindings[binding]);},source payload=>{return payload.value.declarations[binding];},
 frozen payload=>{return blot_check_check::ImportedCatalog{frozen:blot_support::Option<blot_check_check::FrozenProducer>{true,blot_check_check::frozenProducer(payload.value,self_.summaries)},kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..}.declaration(binding);},inactive=>{abort("inactive project declaration catalog");},
}}
fn resolved(self_:CatalogModule,node:u32)->u32 {match self_.owner {typed payload=>{return payload.value.resolved[node];},source payload=>{return payload.value.resolved[node];},_=>{abort("source resolution requires a live source catalog");}}}
enum Editor {none,query{value:EditorQuery}}

struct DiagnosticBuffer {storage:Diagnostic[:]=default<Diagnostic[:]>(),items:Diagnostic[:]=default<Diagnostic[:]>()}
struct Engine {
 source:Project=Project{..},result:CheckedProject=CheckedProject{..},diagnostics:DiagnosticBuffer=DiagnosticBuffer{..},
 retained:const CheckedProject?=null,
 persistent_cache:u32=0,
 persistent_previous:const u8[:][:]=default<const u8[:][:]>(),
 persistent_candidate:const u8[:][:]=default<const u8[:][:]>(),
 persistent_changed:const bool[:]=default<const bool[:]>(),
 source_validation:bool=false,prepare_names:bool=false,execution:blot_check_check::PrivateExecution=blot_check_check::PrivateExecution{..},resolution_remaining:i64=1000000,associated_remaining:i64=1000000,editor:Editor=Editor.none,
 source_modules:blot_support::Option<SourceModule>[:]=default<blot_support::Option<SourceModule>[:]>(),compiled_catalogs:CompiledCatalog[:]=default<CompiledCatalog[:]>(),
}
reusable[] var source_module_runs:blot_support::Option<SourceModule>[>..]=[];
reusable[] var compiled_catalog_runs:CompiledCatalog[>..]=[];
reusable[] var source_declaration_runs:blot_check_check::SourceDeclaration[>..]=[];
fn push(self_:DiagnosticBuffer&,value:Diagnostic)->Error {let length=self_.items.len;let error=blot_support_pooled_buffer::ensure(self_,length+1,owned_Diagnostic);if error!=blot_error::Error.none {return error;}let storage=owned_Diagnostic.realloc_slice(self_.storage,self_.storage.len);assert(blot_support::same_slice_identity(storage,self_.storage));storage[length]=canonicalOwnedDiagnostic(value);self_.items=storage[..length+1];return blot_error::Error.none;}
fn appendSourceDiagnostics(self_:Engine&)->Error {
 let count=self_.source.diagnostics.len;for index in 0..count {let diagnostic=blot_reuse_project::diagnosticAt(self_.source,index);let error=self_.diagnostics.push(Diagnostic{unit:diagnostic.unit,span:diagnostic.span,code:Code.source_validation,source:blot_support::Option<blot_reuse_project::Diagnostic>{true,diagnostic},..});if error!=blot_error::Error.none {return error;}}
 return blot_error::Error.none;
}
fn initEngine(source:Project,execution:blot_check_check::PrivateExecution,editor:Editor)->Engine,Error {
 let result,error=initResult();if error!=blot_error::Error.none {return Engine{..},error;}
 return Engine{source:source,result:result,execution:execution,associated_remaining:min(blot_inference_limits::configured(),9223372036854775807 as u64) as i64,editor:editor,..},blot_error::Error.none;
}
fn deinitSourceModules(self_:Engine&) {
 for &item in self_.source_modules {if item.present {item.value.validation.deinit();releaseOwned(item.value.exports);}}
 if self_.source_modules.len!=0 {source_module_runs.free_slice(self_.source_modules);}self_.source_modules=default<blot_support::Option<SourceModule>[:]>();
 for catalog in self_.compiled_catalogs {releaseOwned(catalog.exports);if catalog.declarations.len!=0 {source_declaration_runs.free_slice(catalog.declarations);}}
 if self_.compiled_catalogs.len!=0 {compiled_catalog_runs.free_slice(self_.compiled_catalogs);}self_.compiled_catalogs=default<CompiledCatalog[:]>();
}
fn deinitDiagnostics(self_:Engine&) {for &item in self_.diagnostics.items {item.deinit();}blot_support_pooled_buffer::deinit(self_.diagnostics,owned_Diagnostic);}
fn deinit(self_:Engine&) {self_.deinitPersistentProducers();self_.deinitDiagnostics();self_.deinitSourceModules();self_.result.deinit();self_=Engine{..};}
fn checkedModule(self_:const Engine&,unit:u32)->const Module? {
 if unit<=self_.result.modules.len && self_.result.modules[unit-1].present {return self_.result.modules[unit-1].value;}
 let retained .= self_.retained;
 if retained {return retained.module(unit);}
 return null;
}
fn catalogModule(self_:const Engine&,unit:u32)->blot_support::Option<CatalogModule> {
 if unit==0 || unit>self_.source.units.len {return blot_support::none<CatalogModule>();}let compiled .= self_.source.compiledModule(unit);if compiled {return blot_support::some(CatalogModule{CatalogOwner.frozen{compiled.interface},self_.compiled_catalogs[unit-1].exports,true, ..});}
 let producer .= self_.persistentProducer(unit);
 if producer {return blot_support::some(CatalogModule{CatalogOwner.frozen{producer.interface},producer.exports,true,producer.summaries, ..});}
 if self_.source_validation {if unit<=self_.source_modules.len && self_.source_modules[unit-1].present {let source:const SourceModule& =self_.source_modules[unit-1].value;return blot_support::some(CatalogModule{CatalogOwner.source{source.validation},source.exports,source.valid, ..});}}
 else {let module .= self_.checkedModule(unit);if module {return blot_support::some(CatalogModule{CatalogOwner.typed{module.checked},module.exports,module.valid, ..});}}
 return blot_support::none<CatalogModule>();
}
fn valueImport(self_:const Engine&,target:ExternalTarget,origin:u32)->blot_check_check::ImportedBinding,Error {
 assert(!self_.source_validation);let compiled .= self_.source.compiledModule(target.unit);var interface=default<blot_check_check::SchemeInterface>();
 if compiled {interface=blot_check_check::ImportedCatalog{frozen:blot_support::Option<blot_check_check::FrozenProducer>{true,blot_check_check::frozenProducer(compiled.interface)},kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:origin, ..}.interface(target.binding);}else {
  let producer .= self_.persistentProducer(target.unit);
  if producer {interface=blot_check_check::ImportedCatalog{frozen:blot_support::Option<blot_check_check::FrozenProducer>{true,blot_check_check::frozenProducer(producer.interface,producer.summaries)},kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:origin, ..}.interface(target.binding);}
  else {
   if self_.persistent_cache!=0 {
    let failure=self_.persistentCache().error;
    if failure!=blot_error::Error.none {return default<blot_check_check::ImportedBinding>(),failure;}
    return default<blot_check_check::ImportedBinding>(),blot_error::Error.invalid_artifact;
   }
   let module .= self_.checkedModule(target.unit);assert(module);interface=checkedInterface(module.checked,target);
  }
 }return blot_check_check::ImportedBinding{ target:target, interface:interface, origin:origin, .. },blot_error::Error.none;
}
fn headerImport(self_:const Engine&,target:ExternalTarget,origin:u32)->blot_check_check::SourceHeader {
 assert(self_.source_validation);let module=self_.catalogModule(target.unit);assert(module.present);let declaration=module.value.declaration(target.binding);return blot_check_check::SourceHeader{ capability_flow:declaration.capability_flow, capability_parameters:declaration.capability_parameters, target:target, named_function:declaration.named_function, origin:origin, .. };
}
fn initCompiledCatalogs(self_:Engine&)->Error {
 self_.compiled_catalogs=compiled_catalog_runs.alloc_slice(self_.source.compiled_modules.len);for &value in self_.compiled_catalogs {value=CompiledCatalog{..};}
 for module,index in self_.source.compiled_modules {if self_.source.compiledModule(index+1)==null {continue;}let exports=owned_Export.alloc_slice(module.exports.len);for old,at in module.exports {exports[at]=Export{old.name,old.target,old.kind,old.catalog, ..};}self_.compiled_catalogs[index].exports=exports;
 if self_.source_validation {let declarations=source_declaration_runs.alloc_slice(module.interface.bindings.len);self_.compiled_catalogs[index].declarations=declarations;let view=blot_check_check::ImportedCatalog{frozen:blot_support::Option<blot_check_check::FrozenProducer>{true,blot_check_check::frozenProducer(module.interface)},kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..};for at in declarations.len {declarations[at]=view.declaration(at as u32);}}}return blot_error::Error.none;
}
fn diagnostic(self_:Engine&,unit:u32,span:Span,code:Code)->Error {return self_.diagnostics.push(Diagnostic{unit:unit,span:span,code:code, ..});}
fn checkOrdered(self_:Engine&,unit:u32)->bool,Error {
 if self_.source.input_mode==blot_reuse_project::InputMode.source && unit==self_.source.entry {let issue=blot_check_check::sourceImportDiagnostic(self_.source.unit(unit).tree);if issue.present {if self_.diagnostics.items.len==0 {let error=self_.diagnostics.push(Diagnostic{unit:unit,span:issue.value.span,code:Code.semantic,semantic:blot_support::some(issue.value.code), ..});if error!=blot_error::Error.none {return false,error;}}return false,blot_error::Error.none;}}
 let error=self_.checkModule(unit);return error==blot_error::Error.none,error;
}

struct ModuleDebit {resolution:i64=0,associated:i64=0,symbols_after:i64=0}
reusable[] var module_debit_runs:ModuleDebit[>..]=[];
fn allocateModuleDebits(count:i64)->ModuleDebit[:] {
 let debits=module_debit_runs.alloc_slice(count);
 for &debit in debits {debit=ModuleDebit{};}
 return debits;
}
fn canonicalModuleDebits(debits:const ModuleDebit[:])->ModuleDebit[:] {
 if debits.len==0 {return default<ModuleDebit[:]>();}
 let run=module_debit_runs.realloc_slice(debits,debits.len);
 assert(blot_support::same_slice_identity(run,debits));
 return run;
}
fn releaseModuleDebits(debits:const ModuleDebit[:]) {if debits.len!=0 {module_debit_runs.free_slice(debits);}}

// The caller has verified that every skipped module's checker inputs are
// equivalent to the checkpoint. Replay its global budget and symbol changes
// at exactly its original position, including for independent modules.
fn checkRetainedModules(source:Project,retained:const CheckedProject&,changed:const bool[:],debits:const ModuleDebit[:],candidate_debits:ModuleDebit[:],symbols:const blot_parse_symbols::Pool&)->CheckedProject,Error {
 let timing=blot_phase_profile::enter(blot_phase_profile::Phase.check);
 var engine,error=initEngine(source,blot_check_check::PrivateExecution{..},Editor.none);
 if error!=blot_error::Error.none {timing.exit();return CheckedProject{..},error;}
 engine.retained .= retained;
 let error=checkChangedModules(engine,changed,debits,candidate_debits,symbols);
 if error!=blot_error::Error.none {engine.deinit();timing.exit();return CheckedProject{..},error;}
 let result=finishProject(engine);
 engine.deinit();timing.exit();
 return result,blot_error::Error.none;
}

fn checkChangedModules(self_:Engine&,changed:const bool[:],debits:const ModuleDebit[:],candidate_debits:ModuleDebit[:],symbols:const blot_parse_symbols::Pool&)->Error {
 let error=self_.result.allocateModules(changed.len);
 if error!=blot_error::Error.none {return error;}
 for unit in self_.source.order.items {
  let before=self_.source.symbols.entries.len;
  let debit=debits[unit-1];
  if debit.symbols_after<before {return blot_error::Error.invalid_artifact;}
  if changed[unit-1] {
   let resolution=self_.resolution_remaining;
   let associated=self_.associated_remaining;
   let continued,error=self_.checkOrdered(unit);
   if error!=blot_error::Error.none {return error;}
   if !continued || self_.diagnostics.items.len!=0 {return blot_error::Error.invalid_artifact;}
   if self_.source.symbols.entries.len!=debit.symbols_after {return blot_error::Error.invalid_artifact;}
   for index in before..debit.symbols_after {
    let symbol=(index+1) as u32;
    if self_.source.symbols.get(symbol)!=symbols.get(symbol) {return blot_error::Error.invalid_artifact;}
   }
   candidate_debits[unit-1]=ModuleDebit{resolution-self_.resolution_remaining,associated-self_.associated_remaining,debit.symbols_after};
  } else {
   if debit.resolution>self_.resolution_remaining || debit.associated>self_.associated_remaining {return blot_error::Error.invalid_artifact;}
   self_.resolution_remaining-=debit.resolution;
   self_.associated_remaining-=debit.associated;
   let error=replaySymbols(self_.source.symbols,symbols,debit.symbols_after);
   if error!=blot_error::Error.none {return error;}
   candidate_debits[unit-1]=debit;
  }
 }
 return blot_error::Error.none;
}

fn replaySymbols(pool:blot_parse_symbols::Pool&,original:const blot_parse_symbols::Pool&,end:i64)->Error {
 for index in pool.entries.len..end {
  let symbol=(index+1) as u32;
  let actual,error=pool.intern(original.get(symbol));
  if error!=blot_error::Error.none {return error;}
  if actual!=symbol {return blot_error::Error.invalid_artifact;}
 }
 return blot_error::Error.none;
}


// Candidate dependencies are published in source order. A changed module never
// receives the previous body or interface at its old ordinal.
fn retainedPersistentPacket(self_:const Engine&,unit:u32)->const u8[:] {
 if unit==0 || unit>self_.persistent_changed.len {return default<const u8[:]>();}
 if self_.persistent_changed[unit-1] {return self_.persistent_candidate[unit-1];}
 return self_.persistent_previous[unit-1];
}
