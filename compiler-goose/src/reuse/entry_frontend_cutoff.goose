// The final entry reuses semantic checking only after its complete prefix settles.
namespace blot_reuse_entry_frontend_cutoff;
import std;
import reuse.project;
import reuse.principal_interface;
import reuse.body_check_cache;
import reuse.dependency_snapshot;
import reuse.dependency_interface_validation;
import reuse.frontend_binding_relocation;
import reuse.frontend_reference_relocation;
import reuse.frontend_method_sources;
import reuse.frozen_dependency;
import check.core;
import check.types;
import check.check;
import backend.runtime_identity;
import backend.opaque_storage;
import support.error;
import support.option;
import support.structural;
type Error=blot_error::Error;
type Project=blot_reuse_project::Project;
type Interface=blot_reuse_principal_interface::Interface;
type Map=blot_reuse_frontend_binding_relocation::Map;
type Targets=blot_reuse_frontend_binding_relocation::Targets;
type Target=blot_reuse_principal_interface::ExternalTarget;
type ExportKind=blot_reuse_frozen_dependency::ExportKind;
struct Import {path:u32,target:u32}
struct Previous {reuse_entry:bool=true,bodies:const blot_reuse_body_check_cache::Cache[:]=default<const blot_reuse_body_check_cache::Cache[:]>(),reuse_modules:bool=false,entry_core:const blot_check_core::Module?=null,entry:u32,prelude:u32,implicit_prelude:bool,names:blot_backend_runtime_identity::View,source:const u8[:],imports:const Import[:]}
enum Color {unknown,green,green_storage,red}
struct Stats {
 comparison_hits:i64=0,offered:i64=0,source_matches:i64=0,namespace_matches:i64=0,compared:i64=0,interfaces_changed:i64=0,surfaces_changed:i64=0,storage_rechecks:i64=0,reused:i64=0,
 interface_changed_unit:u32=0,interface_changed_fields:u64=0,interface_old_bindings:i64=0,interface_new_bindings:i64=0,interface_first_binding:i64=0,interface_comparisons_left:i64=0,interface_progress:blot_reuse_frontend_binding_relocation::Progress=blot_reuse_frontend_binding_relocation::Progress {..},
}
fn confirm<C>(source:const Project&,checked:C&,previous:Previous,stats:Stats&)->bool,Error {
 stats.offered++;let entry=source.entry;
 if source.input_mode!=blot_reuse_project::InputMode.project||entry==0||entry!=source.units.len||source.compiled_modules.len+1!=source.units.len||source.compiled_reuse.len!=source.compiled_modules.len||source.order.len==0||source.order.items[source.order.len-1]!=entry {return false,blot_error::Error.none;}
 if previous.entry!=entry||previous.prelude!=source.prelude_unit||previous.implicit_prelude!=source.unit(entry).implicit_prelude||previous.source!=source.unit(entry).source {return false,blot_error::Error.none;}
 let imports=source.unitImports(entry);if imports.len!=previous.imports.len {return false,blot_error::Error.none;}for current,index in imports {let old=previous.imports[index];if current.path!=old.path||current.target!=old.target {return false,blot_error::Error.none;}}
 stats.source_matches++;if !namespaceMatches(source,previous.names) {return false,blot_error::Error.none;}stats.namespace_matches++;
 for unit in 1..source.compiled_modules.len+1 {if checked.compiledModule(source,unit)!=null {continue;}let same,error=interfaceMatches(source,checked,unit as u32,stats);if error!=blot_error::Error.none||!same {return false,error;}}
 if !storageInputsMatch(source,checked,entry,previous.entry_core,stats) {return false,blot_error::Error.none;}
 let targets=Targets {units:checked.binding_maps, ..};if targets.changes() {let module=previous.entry_core;if !module||!blot_reuse_frontend_reference_relocation::admits(module,targets) {return false,blot_error::Error.none;}}
 stats.reused++;return true,blot_error::Error.none;
}
fn storageInputsMatch<C>(source:const Project&,checked:const C&,unit:u32,previous:const blot_check_core::Module?,stats:Stats&)->bool {
 var changed=false;for color in checked.interface_colors {if color==Color.green_storage {changed=true;break;}}if !changed {return true;}
 let tree .= source.unit(unit).tree;var defines_storage=false;for root in tree.roots.items {if blot_parse_ast::declaration_traits(tree,root).is_opaque {defines_storage=true;break;}}if !defines_storage {return true;}
 let module=previous;
 if module {var remaining:i64=1000000;if module.unit==unit {var stable=true;for nominal in module.nominals {if !nominal.is_opaque||nominal.identity.unit!=unit {continue;}if nominal.constructors.len!=1 {stable=false;break;}let constructor=module.constructors[module.extra[nominal.constructors.start]];if !storageTypeStable(source,checked,module,constructor.payload,0,remaining) {stable=false;break;}}if stable {return true;}}}
 stats.storage_rechecks++;return false;
}
fn storageIdentityStable<C>(source:const Project&,checked:const C&,identity:blot_check_types::NominalIdentity)->bool {
 if identity.unit==0||identity.unit==0xffffffff {return true;}if identity.unit>checked.interface_colors.len {return false;}if checked.interface_colors[identity.unit-1]!=Color.green_storage {return true;}
 let current=checked.modules[identity.unit-1];if !current.present {return false;}let old .= source.compiled_modules[identity.unit-1].interface;
 for before in old.nominals {if before.identity!=identity {continue;}for after in current.value.checked.nominals {if after.identity==identity {return before.storage==after.storage;}}return false;}return false;
}
recursive fn storageTypeStable<C>(source:const Project&,checked:const C&,module:const blot_check_core::Module&,id:u32,depth:i64,remaining:i64&)->bool {
 if depth>=128||remaining==0||id>=module.types.nodes.len {return false;}remaining--;let node=module.types.node(id);
 match node.tag {
  absent,unit,boolean,unsigned32,floating32,never,variable,bound,erased_proof,type_constructor=>{return true;},
  nominal=>{if node.a!=module.unit&&!storageIdentityStable(source,checked,blot_check_types::NominalIdentity {node.a,node.b, ..}) {return false;}for child in module.types.nominalArguments(node) {if !storageTypeStable(source,checked,module,child,depth+1,remaining) {return false;}}return true;},
  array,list,cursor,resolver=>{return storageTypeStable(source,checked,module,node.a,depth+1,remaining);},
  provider=>{return node.c==0&&storageTypeStable(source,checked,module,node.a,depth+1,remaining);},
  function=>{return node.c==0&&storageTypeStable(source,checked,module,node.a,depth+1,remaining)&&storageTypeStable(source,checked,module,node.b,depth+1,remaining);},
  state_provider=>{return storageTypeStable(source,checked,module,node.a,depth+1,remaining)&&storageTypeStable(source,checked,module,node.b,depth+1,remaining)&&storageTypeStable(source,checked,module,node.c,depth+1,remaining);},
  usage=>{return storageTypeStable(source,checked,module,node.a,depth+1,remaining)&&(node.c==0||storageTypeStable(source,checked,module,node.c,depth+1,remaining));},
  product=>{for child in module.types.list(blot_check_types::List {node.a,node.b, ..}) {if !storageTypeStable(source,checked,module,child,depth+1,remaining) {return false;}}return true;},
  record=>{for index in 0..node.b {if !storageTypeStable(source,checked,module,module.types.recordField(node,index).ty,depth+1,remaining) {return false;}}return true;},
  _=>{return false;},
 }
}
fn namespaceMatches(source:const Project&,names:blot_backend_runtime_identity::View)->bool {
 if names.owners.len!=source.units.len||names.symbols.len==0||names.symbols.len>source.symbols.entries.len+1 {return false;}
 for index in source.units.len {let owner=names.owner((index+1) as u32);if !owner.present||owner.value!=source.filename((index+1) as u32) {return false;}}
 for id in 1..names.symbols.len {let symbol=names.symbol(id as u32);if !symbol.present||symbol.value!=source.symbols.get(id as u32) {return false;}}return true;
}
fn semanticEqual(left:blot_reuse_principal_interface::Nominal,right:blot_reuse_principal_interface::Nominal)->bool {
 var before=left;var after=right;if before.is_opaque&&after.is_opaque&&before.storage.kind!=blot_backend_opaque_storage::Kind.unknown&&after.storage.kind!=blot_backend_opaque_storage::Kind.unknown {before.storage=blot_backend_opaque_storage::Storage {..};after.storage=blot_backend_opaque_storage::Storage {..};}return blot_structural::equal(before,after);
}
fn semanticEqual(left:const blot_reuse_principal_interface::Nominal[:],right:const blot_reuse_principal_interface::Nominal[:])->bool {if left.len!=right.len {return false;}for value,index in left {if !semanticEqual(value,right[index]) {return false;}}return true;}
fn semanticEqual(left:Interface,right:Interface)->bool {const for <N,A> in fields<Interface> {if !semanticEqual(left.A,right.A) {return false;}}return true;}
fn semanticEqual<T>(left:T,right:T)->bool {return blot_structural::equal(left,right);}
fn principalEqual(left:Interface,right:Interface)->bool {
 if left.constructors.len!=right.constructors.len {return false;}var before=left;var after=right;before.constructors=default<blot_reuse_principal_interface::Constructor[:]>();after.constructors=default<blot_reuse_principal_interface::Constructor[:]>();if !semanticEqual(before,after) {return false;}
 for old,index in left.constructors {
  let current=right.constructors[index];var candidate=current;
  if old.private&&current.private&&old.nominal<left.nominals.len&&current.nominal<right.nominals.len {let old_parent=left.nominals[old.nominal];let new_parent=right.nominals[current.nominal];if old_parent.is_opaque&&new_parent.is_opaque&&old_parent.storage.kind!=blot_backend_opaque_storage::Kind.unknown&&new_parent.storage.kind!=blot_backend_opaque_storage::Kind.unknown&&old_parent.identity==new_parent.identity&&old.identity.unit==old_parent.identity.unit&&current.identity.unit==new_parent.identity.unit {candidate.identity.decl=old.identity.decl;}}
  if !semanticEqual(old,candidate) {return false;}
 }
 return true;
}
fn interfaceEqual(left:Interface,right:Interface,symbol_count:i64,unit_count:i64)->bool {
 var moved=right;if left.obligation_spans.len==right.obligation_spans.len {moved.obligation_spans=left.obligation_spans;}if semanticEqual(left,moved)||principalEqual(left,moved) {return true;}
 var views:Interface[2]=[left,moved];for &view in views {var count=view.bindings.len;while count!=0 {let binding=view.bindings[count-1];if binding.kind!=blot_reuse_principal_interface::Kind.local&&binding.kind!=blot_reuse_principal_interface::Kind.parameter {break;}let inert=blot_reuse_principal_interface::Binding { private:binding.private, name:0, kind:binding.kind, named_function:false, ty:0, scheme:blot_check_types::Scheme {..}, external:blot_support::none<Target>(), .. };if !semanticEqual(binding,inert) {break;}count--;}view.bindings=view.bindings[..count];}
 if views[0].bindings.len==0||(!semanticEqual(views[0],views[1])&&!principalEqual(views[0],views[1])) {return false;}return blot_reuse_dependency_interface_validation::validate(views[0],symbol_count,unit_count)==blot_error::Error.none;
}
fn interfaceMatches<C>(source:const Project&,checked:C&,unit:u32,stats:Stats&)->bool,Error {
 if unit==0||unit>source.compiled_modules.len {return false,blot_error::Error.none;}
 if checked.interface_colors.len!=0 {match checked.interface_colors[unit-1] {green,green_storage=>{stats.comparison_hits++;return true,blot_error::Error.none;},red=>{stats.comparison_hits++;return false,blot_error::Error.none;},unknown=>{}}}
 var changed=false;let same,error=compareInterface(source,checked,unit,stats,changed);if error!=blot_error::Error.none {return false,error;}
 if checked.interface_colors.len!=0 {var color=Color.red;if same {color=Color.green;if changed {color=Color.green_storage;}}checked.interface_colors[unit-1]=color;}return same,blot_error::Error.none;
}
fn compareInterface<C>(source:const Project&,checked:C&,unit:u32,stats:Stats&,storage_changed:bool&)->bool,Error {
 let old .= source.compiled_modules[unit-1];let current .= checked.modules[unit-1];if !current.present||!current.value.valid||current.value.checked.diagnostics.len!=0 {return false,blot_error::Error.none;}
 let tree .= source.unit(unit).tree;var principal,error=blot_reuse_dependency_snapshot::freezePrincipal(tree,current.value.checked);if error!=blot_error::Error.none {if error==blot_error::Error.out_of_memory {return false,error;}return false,blot_error::Error.none;}
 stats.compared++;var mapping=blot_support::none<Map>();let same,error=comparePublished(source,checked,unit,old,current.value,principal.value,mapping,stats,storage_changed);
 if mapping.present {mapping.value.deinit();}principal.deinit();return same,error;
}
fn comparePublished<C,M>(source:const Project&,checked:C&,unit:u32,old:const blot_reuse_frozen_dependency::Module&,current:const M&,published:const Interface&,mapping:blot_support::Option<Map>&,stats:Stats&,storage_changed:bool&)->bool,Error {
 if !interfaceEqual(old.interface,published,source.symbols.entries.len+1,source.units.len) {
  if unit>checked.binding_maps.len {stats.interfaces_changed++;return false,blot_error::Error.none;}
  var methods=blot_reuse_frontend_method_sources::Context {before:old.core,after:current.checked,names:source.symbols, ..};var comparisons:i64=0;var progress=blot_reuse_frontend_binding_relocation::Progress {..};
  let __alias_field_62_units: const blot_support::Option<blot_reuse_frontend_binding_relocation::Map>[:] = checked.binding_maps; let __alias_field_63_methods: blot_support::Option<blot_reuse_frontend_method_sources::Sources> = blot_support::some(methods.view()); let __alias_field_64_comparisons_left: i64? .= comparisons; let __alias_field_65_progress: blot_reuse_frontend_binding_relocation::Progress? .= progress; let candidate,error=blot_reuse_frontend_binding_relocation::compare(old.interface,published,Targets { progress: __alias_field_65_progress, units: __alias_field_62_units, methods: __alias_field_63_methods, comparisons_left: __alias_field_64_comparisons_left, .. });if error!=blot_error::Error.none {return false,error;}mapping=candidate;
  if !mapping.present {
   if stats.interface_changed_unit==0 {
    stats.interface_changed_unit=unit;stats.interface_comparisons_left=comparisons;stats.interface_progress=progress;stats.interface_old_bindings=old.interface.bindings.len;stats.interface_new_bindings=published.bindings.len;
    var index:u32=0;const for <N,A> in fields<Interface> {if !semanticEqual(old.interface.A,published.A) {stats.interface_changed_fields|=(1 as u64)<<index;}index++;}
    for index in 0..min(old.interface.bindings.len,published.bindings.len) {if !semanticEqual(old.interface.bindings[index],published.bindings[index]) {stats.interface_first_binding=index;break;}}
   }
   stats.interfaces_changed++;return false,blot_error::Error.none;
  }
 }
 if current.exports.len!=old.exports.len {return false,blot_error::Error.none;}
 for fresh,index in current.exports {let prior=old.exports[index];let target=relocatedTarget(unit,mapping,checked.binding_maps,prior.target);let catalog=relocatedCatalog(unit,mapping,checked.binding_maps,prior);if !target.present||!catalog.present {return false,blot_error::Error.none;}if fresh.name!=prior.name||fresh.target!=target.value||fresh.kind!=prior.kind||fresh.catalog!=catalog.value {stats.surfaces_changed++;return false,blot_error::Error.none;}}
 let tree .= source.unit(unit).tree;var fixity_index:i64=0;
 for id in tree.roots.items {
  if tree.node(id).tag!=blot_parse_ast::tag_fixity_decl {continue;}if fixity_index>=old.fixities.len {return false,blot_error::Error.none;}let fresh=tree.fixity(id);let prior=old.fixities[fixity_index];fixity_index++;
  let binding=current.checked.resolved[id];if binding==0||binding>=current.checked.bindings.len {return false,blot_error::Error.none;}var target=Target {unit,binding, ..};if current.checked.bindings[binding].external.present {target=current.checked.bindings[binding].external.value;}let producer=relocatedTarget(unit,mapping,checked.binding_maps,prior.producer);if !producer.present {return false,blot_error::Error.none;}
  if fresh.operator!=prior.operator||fresh.target!=prior.target||fresh.precedence!=prior.precedence||fresh.association!=prior.association||fresh.named!=prior.named||target!=producer.value {return false,blot_error::Error.none;}
 }
 if fixity_index!=old.fixities.len {return false,blot_error::Error.none;}
 for before,index in old.interface.nominals {if index==0||before.private {continue;}var at=index;if mapping.present {let translated=mapping.value.catalog(blot_reuse_frozen_dependency::ExportKind.nominal,index as u32);if !translated.present {return false,blot_error::Error.none;}at=translated.value;}if at>=published.nominals.len {return false,blot_error::Error.none;}let after=published.nominals[at];if before.is_opaque&&before.storage!=after.storage {storage_changed=true;}}
 if mapping.present&&mapping.value.changes() {checked.binding_maps[unit-1]=mapping;mapping.present=false;}return true,blot_error::Error.none;
}
fn relocatedCatalog(unit:u32,mapping:blot_support::Option<Map>,prior:const blot_support::Option<Map>[:],exported:blot_reuse_frozen_dependency::Export)->blot_support::Option<u32> {
 if exported.target.unit==unit {if !mapping.present {return blot_support::some(exported.catalog);}return mapping.value.catalog(exported.kind,exported.catalog);}let mapped=Targets {units:prior, ..}.exported(exported);if !mapped.present {return blot_support::none<u32>();}return blot_support::some(mapped.value.catalog);
}
fn relocatedTarget(unit:u32,mapping:blot_support::Option<Map>,prior:const blot_support::Option<Map>[:],target:Target)->blot_support::Option<Target> {
 if target.binding==0 {return blot_support::some(target);}if target.unit==unit {if !mapping.present {return blot_support::some(target);}let translated=mapping.value.binding(target.binding);if !translated.present {return blot_support::none<Target>();}return blot_support::some(Target {unit,translated.value, ..});}return Targets {units:prior, ..}.target(target);
}
