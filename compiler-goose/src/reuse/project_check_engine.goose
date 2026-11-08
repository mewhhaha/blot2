// One live checker context supplies typed producer services during inference.
namespace blot_reuse_project_check;
import .project_check;
import inference_limits;
import reuse.module_frontend_cutoff;
import phase_profile;
struct SourceModule {validation:blot_check_check::SourceValidation,exports:Export[:],valid:bool}
struct CompiledCatalog {exports:Export[:]=default<Export[:]>(),declarations:blot_check_check::SourceDeclaration[:]=default<blot_check_check::SourceDeclaration[:]>()}
enum CatalogOwner {inactive,typed{value:const Checked&},source{value:const blot_check_check::SourceValidation&},frozen{value:const blot_reuse_principal_interface::Interface&}}
struct CatalogModule {owner:CatalogOwner=CatalogOwner.inactive,exports:const Export[:]=default<const Export[:]>(),valid:bool=false}
fn catalog(self_:CatalogModule)->blot_check_check::DeclarationCatalog {match self_.owner {
 typed payload=>{return blot_check_check::declarationCatalog(payload.value);},source payload=>{return blot_check_check::declarationCatalog(payload.value);},
 frozen payload=>{return blot_check_check::ImportedCatalog{frozen:payload.value,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..}.catalog();},inactive=>{abort("inactive project declaration catalog");},
}}
fn declaration(self_:CatalogModule,binding:u32)->blot_check_check::SourceDeclaration {match self_.owner {
 typed payload=>{return blot_check_check::sourceDeclaration(payload.value.bindings[binding]);},source payload=>{return payload.value.declarations[binding];},
 frozen payload=>{return blot_check_check::ImportedCatalog{frozen:payload.value,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..}.declaration(binding);},inactive=>{abort("inactive project declaration catalog");},
}}
fn resolved(self_:CatalogModule,node:u32)->u32 {match self_.owner {typed payload=>{return payload.value.resolved[node];},source payload=>{return payload.value.resolved[node];},_=>{abort("source resolution requires a live source catalog");}}}
enum Editor {none,query{value:EditorQuery}}
// Offers retain identities, while the previous project retains cache ownership.
struct BodyOffer {lease:u32=0,generation:u64=0}
type BodyOffers=blot_support_pooled_map::Map<u32,BodyOffer>;
struct DiagnosticBuffer {storage:Diagnostic[:]=default<Diagnostic[:]>(),items:Diagnostic[:]=default<Diagnostic[:]>()}
struct Engine {
 slot:u32=0,generation:u64=0,live:bool=false,previous_bodies:BodyOffers=BodyOffers{..},retain_bodies:bool=false,source:Project=Project{..},result:CheckedProject=CheckedProject{..},diagnostics:DiagnosticBuffer=DiagnosticBuffer{..},
 source_validation:bool=false,prepare_names:bool=false,execution:blot_check_check::PrivateExecution=blot_check_check::PrivateExecution{..},resolution_remaining:i64=1000000,associated_remaining:i64=1000000,editor:Editor=Editor.none,
 source_modules:blot_support::Option<SourceModule>[:]=default<blot_support::Option<SourceModule>[:]>(),compiled_catalogs:CompiledCatalog[:]=default<CompiledCatalog[:]>(),
}
reusable var engines:Engine[>..]=[];
reusable[] var offer_slots:dictionary_slot<u32,BodyOffer>[>..]=[];
reusable[] var source_module_runs:blot_support::Option<SourceModule>[>..]=[];
reusable[] var compiled_catalog_runs:CompiledCatalog[>..]=[];
reusable[] var source_declaration_runs:blot_check_check::SourceDeclaration[>..]=[];
fn push(self_:DiagnosticBuffer&,value:Diagnostic)->Error {return blot_support_pooled_buffer::push(self_,value,owned_Diagnostic);}
fn initEngine(source:const Project&,execution:blot_check_check::PrivateExecution,editor:Editor,retain_bodies:bool)->Engine?,Error {
 if engines.len>=0xffffffff {return null,blot_error::Error.out_of_memory;}let result,error=initResult();if error!=blot_error::Error.none {return null,error;}let generation=blot_native::fresh_owner_id();                let __field_order_533_generation: u64 = generation; let __field_order_534_live: bool = true; let __field_order_535_source: blot_reuse_project_check::Project = source; let __field_order_536_result: blot_reuse_project_check::CheckedProject = result; let __field_order_537_execution: blot_check_check::PrivateExecution = execution; let __field_order_538_editor: blot_reuse_project_check::Editor = editor; let __field_order_539_retain_bodies: bool = retain_bodies; let __field_order_540_associated_remaining: i64 = min(blot_inference_limits::configured(),9223372036854775807 as u64) as i64; let at=engines.alloc_index(Engine{ generation: __field_order_533_generation, live: __field_order_534_live, retain_bodies: __field_order_539_retain_bodies, source: __field_order_535_source, result: __field_order_536_result, execution: __field_order_537_execution, associated_remaining: __field_order_540_associated_remaining, editor: __field_order_538_editor, .. });engines[at].slot=(at+1) as u32;return engines[at],blot_error::Error.none;
}
fn deinitSourceModules(self_:Engine&) {
 for &item in self_.source_modules {if item.present {item.value.validation.deinit();releaseOwned(item.value.exports);}}
 if self_.source_modules.len!=0 {source_module_runs.free_slice(self_.source_modules);}self_.source_modules=default<blot_support::Option<SourceModule>[:]>();
 for catalog in self_.compiled_catalogs {releaseOwned(catalog.exports);if catalog.declarations.len!=0 {source_declaration_runs.free_slice(catalog.declarations);}}
 if self_.compiled_catalogs.len!=0 {compiled_catalog_runs.free_slice(self_.compiled_catalogs);}self_.compiled_catalogs=default<CompiledCatalog[:]>();
}
fn deinitDiagnostics(self_:Engine&) {for &item in self_.diagnostics.items {item.deinit();}blot_support_pooled_buffer::deinit(self_.diagnostics,owned_Diagnostic);}
fn deinit(self_:Engine&) {assert(self_.live);self_.deinitDiagnostics();self_.deinitSourceModules();blot_support_pooled_map::deinit(self_.previous_bodies,offer_slots);self_.result.deinit();let at=self_.slot-1;self_=Engine{..};engines.free(at);}
fn catalogModule(self_:const Engine&,unit:u32)->blot_support::Option<CatalogModule> {
 if unit==0 || unit>self_.source.units.len {return blot_support::none<CatalogModule>();}let compiled .= self_.result.compiledModule(self_.source,unit);if compiled {return blot_support::some(CatalogModule{CatalogOwner.frozen{compiled.interface},self_.compiled_catalogs[unit-1].exports,true, ..});}
 if self_.source_validation {if unit<=self_.source_modules.len && self_.source_modules[unit-1].present {let source:const SourceModule& =self_.source_modules[unit-1].value;return blot_support::some(CatalogModule{CatalogOwner.source{source.validation},source.exports,source.valid, ..});}}
 else if unit<=self_.result.modules.len && self_.result.modules[unit-1].present {let module:const Module& =self_.result.modules[unit-1].value;return blot_support::some(CatalogModule{CatalogOwner.typed{module.checked},module.exports,module.valid, ..});}
 return blot_support::none<CatalogModule>();
}
fn valueImport(self_:const Engine&,target:ExternalTarget,origin:u32)->blot_check_check::ImportedBinding {
 assert(!self_.source_validation);let compiled .= self_.result.compiledModule(self_.source,target.unit);var interface=default<blot_check_check::SchemeInterface>();
 if compiled {interface=blot_check_check::ImportedCatalog{frozen:compiled.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:origin, ..}.interface(target.binding);}else {interface=self_.result.interface(target);}return blot_check_check::ImportedBinding{ target:target, interface:interface, origin:origin, .. };
}
fn headerImport(self_:const Engine&,target:ExternalTarget,origin:u32)->blot_check_check::SourceHeader {
 assert(self_.source_validation);let module=self_.catalogModule(target.unit);assert(module.present);let declaration=module.value.declaration(target.binding);return blot_check_check::SourceHeader{ capability_flow:declaration.capability_flow, capability_parameters:declaration.capability_parameters, target:target, named_function:declaration.named_function, origin:origin, .. };
}
fn initCompiledCatalogs(self_:Engine&)->Error {
 self_.compiled_catalogs=compiled_catalog_runs.alloc_slice(self_.source.compiled_modules.len);for &value in self_.compiled_catalogs {value=CompiledCatalog{..};}
 for module,index in self_.source.compiled_modules {if self_.result.compiledModule(self_.source,index+1)==null {continue;}let exports=owned_Export.alloc_slice(module.exports.len);for old,at in module.exports {exports[at]=Export{old.name,old.target,old.kind,old.catalog, ..};}self_.compiled_catalogs[index].exports=exports;
 if self_.source_validation {let declarations=source_declaration_runs.alloc_slice(module.interface.bindings.len);self_.compiled_catalogs[index].declarations=declarations;let view=blot_check_check::ImportedCatalog{frozen:module.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0, ..};for at in declarations.len {declarations[at]=view.declaration(at as u32);}}}return blot_error::Error.none;
}
fn recoverModule(self_:Engine&,unit:u32)->bool,Error {
 let previous:const FrozenModule& =self_.source.compiled_modules[unit-1];let targets=blot_reuse_frontend_binding_relocation::Targets{units:self_.result.binding_maps, ..};var relocated=default<blot_reuse_dependency_payload::Owned<FrozenModule>>();
 if targets.changes() {let changed=blot_reuse_frontend_reference_relocation::changes(previous,targets);if !changed.present {return false,blot_error::Error.none;}if changed.value {let value,error=blot_reuse_dependency_payload::clone(previous);if error!=blot_error::Error.none {return false,error;}relocated=value;let error=blot_reuse_frontend_reference_relocation::rewrite(relocated.owner,relocated.value,targets);if error!=blot_error::Error.none {relocated.deinit();return false,blot_error::Error.none;}}}
 var selected=previous;if relocated.owner.lease!=0 {selected=relocated.value;}let exports=owned_Export.alloc_slice(selected.exports.len);for old,index in selected.exports {exports[index]=Export{old.name,old.target,old.kind,old.catalog, ..};}
 self_.compiled_catalogs[unit-1].exports=exports;if relocated.owner.lease!=0 {self_.result.relocated_modules[unit-1]=blot_support::some(relocated.value);result_states[self_.result.owner.slot-1].relocated[unit-1]=relocated.owner;}
 self_.result.reused_modules[unit-1]=true;self_.result.module_cutoff.reused+=1;return true,blot_error::Error.none;
}
fn offerBodies(self_:Engine&,previous:blot_support::Option<blot_reuse_entry_frontend_cutoff::Previous>)->Error {
 if !previous.present {return blot_error::Error.none;}let old=previous.value;if old.bodies.len!=old.names.owners.len {return blot_error::Error.none;}
 for &body,index in old.bodies {
  let filename=old.names.owner((index+1) as u32);if !filename.present {continue;}
  // All current module filenames are already interned; unrelated old names cannot be requested.
  let symbol,found=self_.source.symbols.lookup(filename.value);if !found {continue;}
  var offer=BodyOffer{body.lease,body.generation};
  if blot_support_pooled_map::contains(self_.previous_bodies,symbol) {offer=BodyOffer{..};}
  blot_support_pooled_map::insert(self_.previous_bodies,symbol,offer,offer_slots);
 }return blot_error::Error.none;
}
fn offeredBody(self_:const Engine&,filename:u32)->const blot_reuse_body_check_cache::Cache? {
 let found .= blot_support_pooled_map::get(self_.previous_bodies,filename);if !found {return null;}let offer=found;
 if offer.lease==0 {return null;}
 assert(offer.lease-1<blot_reuse_body_check_cache::cache_states.len);
 let state:const blot_reuse_body_check_cache::CacheState& =blot_reuse_body_check_cache::cache_states[offer.lease-1];
 assert(state.live && state.generation==offer.generation);return state.canonical;
}

fn diagnostic(self_:Engine&,unit:u32,span:Span,code:Code)->Error {return self_.diagnostics.push(Diagnostic{unit:unit,span:span,code:code, ..});}
fn checkOrdered(self_:Engine&,unit:u32,previous:blot_support::Option<blot_reuse_entry_frontend_cutoff::Previous>)->bool,Error {
 if self_.source.input_mode==blot_reuse_project::InputMode.source && unit==self_.source.entry {let issue=blot_check_check::sourceImportDiagnostic(self_.source.unit(unit).tree);if issue.present {if self_.diagnostics.items.len==0 {let error=self_.diagnostics.push(Diagnostic{unit:unit,span:issue.value.span,code:Code.semantic,semantic:blot_support::some(issue.value.code), ..});if error!=blot_error::Error.none {return false,error;}}return false,blot_error::Error.none;}}
 if unit==self_.source.entry && !self_.source_validation && self_.diagnostics.items.len==0 && previous.present && previous.value.reuse_entry {let confirmed,error=blot_reuse_entry_frontend_cutoff::confirm(self_.source,self_.result,previous.value,self_.result.entry_cutoff);if error!=blot_error::Error.none || confirmed {return confirmed,error;}}
 if unit!=self_.source.entry && self_.result.reused_modules.len!=0 && self_.diagnostics.items.len==0 && previous.present {let confirmed,error=blot_reuse_module_frontend_cutoff::confirm(self_.source,self_.result,previous.value,unit,self_.result.module_cutoff);if error!=blot_error::Error.none {return false,error;}if confirmed {let recovered,error=self_.recoverModule(unit);if error!=blot_error::Error.none || recovered {return recovered,error;}}}
 let error=self_.checkModule(unit);return error==blot_error::Error.none,error;
}
