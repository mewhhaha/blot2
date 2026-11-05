// One live checker context supplies typed producer services during inference.
namespace blot_reuse_project_check;
import .project_check;
import inference_limits;
import reuse.module_frontend_cutoff;
import phase_profile;
struct SourceModule {validation:blot_check_check::SourceValidation,exports:Export[:],valid:bool}
struct CompiledCatalog {exports:Export[:]=[],declarations:blot_check_check::SourceDeclaration[:]=[]}
enum CatalogOwner {inactive,typed{value:const Checked&},source{value:const blot_check_check::SourceValidation&},frozen{value:const blot_reuse_principal_interface::Interface&}}
struct CatalogModule {owner:CatalogOwner=CatalogOwner.inactive,exports:const Export[:]=[],valid:bool=false}
fn catalog(self:CatalogModule)->blot_check_check::DeclarationCatalog {match self.owner {
 CatalogOwner.typed payload=>{return blot_check_check::declarationCatalog(payload.value);},CatalogOwner.source payload=>{return blot_check_check::declarationCatalog(payload.value);},
 CatalogOwner.frozen payload=>{return blot_check_check::ImportedCatalog{frozen:payload.value,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0}.catalog();},CatalogOwner.inactive=>{abort("inactive project declaration catalog");},
}}
fn declaration(self:CatalogModule,binding:u32)->blot_check_check::SourceDeclaration {match self.owner {
 CatalogOwner.typed payload=>{return blot_check_check::sourceDeclaration(payload.value.bindings[binding]);},CatalogOwner.source payload=>{return payload.value.declarations[binding];},
 CatalogOwner.frozen payload=>{return blot_check_check::ImportedCatalog{frozen:payload.value,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0}.declaration(binding);},CatalogOwner.inactive=>{abort("inactive project declaration catalog");},
}}
fn resolved(self:CatalogModule,node:u32)->u32 {match self.owner {CatalogOwner.typed payload=>{return payload.value.resolved[node];},CatalogOwner.source payload=>{return payload.value.resolved[node];},_=>{abort("source resolution requires a live source catalog");}}}
enum Editor {none,query{value:EditorQuery}}
type BodyOffers=blot_support_pooled_map::Map<const u8[:],const blot_reuse_body_check_cache::Cache?>;
struct DiagnosticBuffer {storage:Diagnostic[:]=[],items:Diagnostic[:]=[]}
struct Engine {
 slot:u32=0,generation:u64=0,live:bool=false,previous_bodies:BodyOffers=BodyOffers{},retain_bodies:bool=false,source:Project=Project{},result:CheckedProject=CheckedProject{},diagnostics:DiagnosticBuffer=DiagnosticBuffer{},
 source_validation:bool=false,prepare_names:bool=false,execution:blot_check_check::PrivateExecution=blot_check_check::PrivateExecution{},resolution_remaining:i64=1000000,associated_remaining:i64=1000000,editor:Editor=Editor.none,
 source_modules:blot_support::Option<SourceModule>[:]=[],compiled_catalogs:CompiledCatalog[:]=[],
}
reusable var engines:Engine[>..]=[];
reusable[] var offer_slots:dictionary_slot<const u8[:],const blot_reuse_body_check_cache::Cache?>[>..]=[];
reusable[] var source_module_runs:blot_support::Option<SourceModule>[>..]=[];
reusable[] var compiled_catalog_runs:CompiledCatalog[>..]=[];
reusable[] var source_declaration_runs:blot_check_check::SourceDeclaration[>..]=[];
fn push(self:DiagnosticBuffer&,value:Diagnostic)->Error {return blot_support_pooled_buffer::push(self,value,owned_Diagnostic);}
fn initEngine(source:const Project&,execution:blot_check_check::PrivateExecution,editor:Editor,retain_bodies:bool)->Engine?,Error {
 if engines.len>=0xffffffff {return null,Error.out_of_memory;}let result,error=initResult();if error!=Error.none {return null,error;}let generation=blot_native::fresh_owner_id();let at=engines.alloc_index(Engine{generation:generation,live:true,source:source,result:result,execution:execution,editor:editor,retain_bodies:retain_bodies,associated_remaining:blot_inference_limits::configured()});engines[at].slot=(at+1) as u32;return engines[at],Error.none;
}
fn deinitSourceModules(self:Engine&) {
 for &item in self.source_modules {if item.present {item.value.validation.deinit();releaseOwned(item.value.exports);}}
 if self.source_modules.len!=0 {source_module_runs.free_slice(self.source_modules);}self.source_modules=[];
 for catalog in self.compiled_catalogs {releaseOwned(catalog.exports);if catalog.declarations.len!=0 {source_declaration_runs.free_slice(catalog.declarations);}}
 if self.compiled_catalogs.len!=0 {compiled_catalog_runs.free_slice(self.compiled_catalogs);}self.compiled_catalogs=[];
}
fn deinitDiagnostics(self:Engine&) {for &item in self.diagnostics.items {item.deinit();}blot_support_pooled_buffer::deinit(self.diagnostics,owned_Diagnostic);}
fn deinit(self:Engine&) {assert(self.live);self.deinitDiagnostics();self.deinitSourceModules();blot_support_pooled_map::deinit(self.previous_bodies,offer_slots);self.result.deinit();let at=self.slot-1;self=Engine{};engines.free(at);}
fn catalogModule(self:const Engine&,unit:u32)->blot_support::Option<CatalogModule> {
 if unit==0 || unit>self.source.units.len {return blot_support::none<CatalogModule>();}let compiled .= self.result.compiledModule(self.source,unit);if compiled {return blot_support::some(CatalogModule{CatalogOwner.frozen{compiled.interface},self.compiled_catalogs[unit-1].exports,true});}
 if self.source_validation {if unit<=self.source_modules.len && self.source_modules[unit-1].present {let source:const SourceModule&=self.source_modules[unit-1].value;return blot_support::some(CatalogModule{CatalogOwner.source{source.validation},source.exports,source.valid});}}
 else if unit<=self.result.modules.len && self.result.modules[unit-1].present {let module:const Module&=self.result.modules[unit-1].value;return blot_support::some(CatalogModule{CatalogOwner.typed{module.checked},module.exports,module.valid});}
 return blot_support::none<CatalogModule>();
}
fn valueImport(self:const Engine&,target:ExternalTarget,origin:u32)->blot_check_check::ImportedBinding {
 assert(!self.source_validation);let compiled .= self.result.compiledModule(self.source,target.unit);var interface=default<blot_check_check::SchemeInterface>();
 if compiled {interface=blot_check_check::ImportedCatalog{frozen:compiled.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:origin}.interface(target.binding);}else {interface=self.result.interface(target);}return blot_check_check::ImportedBinding{target:target,origin:origin,interface:interface};
}
fn headerImport(self:const Engine&,target:ExternalTarget,origin:u32)->blot_check_check::SourceHeader {
 assert(self.source_validation);let module=self.catalogModule(target.unit);assert(module.present);let declaration=module.value.declaration(target.binding);return blot_check_check::SourceHeader{target:target,origin:origin,capability_flow:declaration.capability_flow,capability_parameters:declaration.capability_parameters,named_function:declaration.named_function};
}
fn initCompiledCatalogs(self:Engine&)->Error {
 self.compiled_catalogs=compiled_catalog_runs.alloc_slice(self.source.compiled_modules.len);for &value in self.compiled_catalogs {value=CompiledCatalog{};}
 for module,index in self.source.compiled_modules {if self.result.compiledModule(self.source,index+1)==null {continue;}let exports=owned_Export.alloc_slice(module.exports.len);for old,at in module.exports {exports[at]=Export{old.name,old.target,old.kind,old.catalog};}self.compiled_catalogs[index].exports=exports;
 if self.source_validation {let declarations=source_declaration_runs.alloc_slice(module.interface.bindings.len);self.compiled_catalogs[index].declarations=declarations;let view=blot_check_check::ImportedCatalog{frozen:module.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0};for at in declarations.len {declarations[at]=view.declaration(at as u32);}}}return Error.none;
}
fn recoverModule(self:Engine&,unit:u32)->bool,Error {
 let previous:const FrozenModule&=self.source.compiled_modules[unit-1];let targets=blot_reuse_frontend_binding_relocation::Targets{units:self.result.binding_maps};var relocated=default<blot_reuse_dependency_payload::Owned<FrozenModule>>();
 if targets.changes() {let changed=blot_reuse_frontend_reference_relocation::changes(previous,targets);if !changed.present {return false,Error.none;}if changed.value {let value,error=blot_reuse_dependency_payload::clone(previous);if error!=Error.none {return false,error;}relocated=value;let error=blot_reuse_frontend_reference_relocation::rewrite(relocated.owner,relocated.value,targets);if error!=Error.none {relocated.deinit();return false,Error.none;}}}
 var selected=previous;if relocated.owner.lease!=0 {selected=relocated.value;}let exports=owned_Export.alloc_slice(selected.exports.len);for old,index in selected.exports {exports[index]=Export{old.name,old.target,old.kind,old.catalog};}
 self.compiled_catalogs[unit-1].exports=exports;if relocated.owner.lease!=0 {self.result.relocated_modules[unit-1]=blot_support::some(relocated.value);result_states[self.result.owner.slot-1].relocated[unit-1]=relocated.owner;}
 self.result.reused_modules[unit-1]=true;self.result.module_cutoff.reused+=1;return true,Error.none;
}
fn offerBodies(self:Engine&,previous:blot_support::Option<blot_reuse_entry_frontend_cutoff::Previous>)->Error {
 if !previous.present {return Error.none;}let old=previous.value;if old.bodies.len!=old.names.owners.len {return Error.none;}
 for &body,index in old.bodies {let filename=old.names.owner((index+1) as u32);if !filename.present {continue;}if blot_support_pooled_map::contains(self.previous_bodies,filename.value) {blot_support_pooled_map::insert(self.previous_bodies,filename.value,null,offer_slots);}else {blot_support_pooled_map::insert(self.previous_bodies,filename.value,body,offer_slots);}}return Error.none;
}
fn diagnostic(self:Engine&,unit:u32,span:Span,code:Code)->Error {return self.diagnostics.push(Diagnostic{unit:unit,span:span,code:code});}
fn checkOrdered(self:Engine&,unit:u32,previous:blot_support::Option<blot_reuse_entry_frontend_cutoff::Previous>)->bool,Error {
 if self.source.input_mode==blot_reuse_project::InputMode.source && unit==self.source.entry {let issue=blot_check_check::sourceImportDiagnostic(self.source.unit(unit).tree);if issue.present {if self.diagnostics.items.len==0 {let error=self.diagnostics.push(Diagnostic{unit:unit,span:issue.value.span,code:Code.semantic,semantic:blot_support::some(issue.value.code)});if error!=Error.none {return false,error;}}return false,Error.none;}}
 if unit==self.source.entry && !self.source_validation && self.diagnostics.items.len==0 && previous.present && previous.value.reuse_entry {let confirmed,error=blot_reuse_entry_frontend_cutoff::confirm(self.source,self.result,previous.value,self.result.entry_cutoff);if error!=Error.none || confirmed {return confirmed,error;}}
 if unit!=self.source.entry && self.result.reused_modules.len!=0 && self.diagnostics.items.len==0 && previous.present {let confirmed,error=blot_reuse_module_frontend_cutoff::confirm(self.source,self.result,previous.value,unit,self.result.module_cutoff);if error!=Error.none {return false,error;}if confirmed {let recovered,error=self.recoverModule(unit);if error!=Error.none || recovered {return recovered,error;}}}
 let error=self.checkModule(unit);return error==Error.none,error;
}
