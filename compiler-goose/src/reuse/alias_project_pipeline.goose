// Freeze a successfully checked fresh project for source-free emission.
namespace blot_reuse_alias_project_pipeline;
import reuse.project;
import reuse.project_check;
import reuse.dependency_payload;
import check.core;
import check.core_builder;
import backend.core_backend;
import backend.runtime_identity;
import support.error;
import support.option;
type Error=blot_error::Error;
type Core=blot_check_core::Module;
type Owner=blot_reuse_dependency_payload::Owner;
reusable[] var unit_owners:Owner[>..]=[];
struct OwnedCore {units:Core[:]=default<Core[:]>(),names:blot_backend_runtime_identity::Metadata=blot_backend_runtime_identity::Metadata{..},order:u32[:]=default<u32[:]>(),entry:u32=0,prelude:u32=0,source_mode:bool=false,body_lowerings:i64=0,owner:Owner=Owner{..},modules:Owner[:]=default<Owner[:]>()}
fn deinit(self_:OwnedCore&) {for &owner in self_.modules {owner.release();}if self_.modules.len!=0 {unit_owners.free_slice(self_.modules);}self_.owner.release();self_=OwnedCore{..};}
fn emit(self_:const OwnedCore&,workspace:blot_backend_core_backend::CompileWorkspace&)->blot_backend_core_backend::Result,Error {
 let staged=blot_backend_core_backend::pinWorkspaceInputs(workspace,self_.units,self_.owner,self_.modules,[]);if staged!=blot_error::Error.none {return default<blot_backend_core_backend::Result>(),staged;}
 let value,error=blot_backend_core_backend::compileWithOptions(workspace,self_.units,self_.entry,blot_backend_core_backend::CompileOptions{identity:blot_support::some(self_.names.view()),unit_order:self_.order,diagnostic_source_mode:self_.source_mode,diagnostic_prelude_unit:self_.prelude,..});if error!=blot_error::Error.none {return default<blot_backend_core_backend::Result>(),error;}var result=value;
 let pinned=blot_backend_core_backend::pinResult(result,self_.owner,self_.modules,[]);if pinned!=blot_error::Error.none {result.deinit();return default<blot_backend_core_backend::Result>(),pinned;}return result,blot_error::Error.none;
}
fn lowerChecked<E>(executor:E&,source:const blot_reuse_project::Project&,checked:const blot_reuse_project_check::CheckedProject&)->OwnedCore,Error {
 if source.diagnostics.len!=0 || checked.diagnostics.len!=0 || source.compiled_modules.len!=0 {return OwnedCore{..},blot_error::Error.unqualified_project;}
 let opened,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return OwnedCore{..},error;}var result=OwnedCore{ entry:source.entry, prelude:source.prelude_unit, source_mode:source.input_mode==blot_reuse_project::InputMode.source, owner:opened, .. };var published=false;
 let units,error=result.owner.alloc<Core>(source.units.len);if error!=blot_error::Error.none {let __cleanup_result_1_0: OwnedCore = OwnedCore{..}; let __cleanup_result_1_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_1_0, __cleanup_result_1_1;}result.units=units;result.modules=unit_owners.alloc_slice(units.len);for &owner in result.modules {owner=Owner{..};}
 for unit,index in source.units.items {let id=(index+1) as u32;let lowered,error=blot_check_core_builder::lowerWithOrigins(unit.tree,source.symbols,checked.module(id).checked,blot_reuse_project_check::moduleOrigins(source));if error!=blot_error::Error.none {let __cleanup_result_2_0: OwnedCore = OwnedCore{..}; let __cleanup_result_2_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_2_0, __cleanup_result_2_1;}result.units[index]=lowered.value;result.modules[index]=lowered.owner;if lowered.value.diagnostics.len!=0 {let __cleanup_result_3_0: OwnedCore = OwnedCore{..}; let __cleanup_result_3_1: Error = blot_error::Error.lowering_diagnostics; {if !published {result.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;}result.units[index].unit=id;result.body_lowerings+=lowered.value.body_lowerings;}
 var owners:blot_backend_runtime_identity::Owner[>..<]=[];for index in units.len {let id=(index+1) as u32;owners.push(blot_backend_runtime_identity::Owner{id,source.filename(id), ..});}
 let captured,error=blot_backend_runtime_identity::capture(source.symbols,owners[..],units.len);if error!=blot_error::Error.none {let __cleanup_result_4_0: OwnedCore = OwnedCore{..}; let __cleanup_result_4_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_4_0, __cleanup_result_4_1;}var names=captured;
 let bytes,error=result.owner.copy(names.bytes);if error!=blot_error::Error.none {let __cleanup_result_5_0: OwnedCore = OwnedCore{..}; let __cleanup_result_5_1: Error = error; {names.deinit();} {if !published {result.deinit();}} return __cleanup_result_5_0, __cleanup_result_5_1;}let symbols,error=result.owner.copy(names.symbols);if error!=blot_error::Error.none {let __cleanup_result_6_0: OwnedCore = OwnedCore{..}; let __cleanup_result_6_1: Error = error; {names.deinit();} {if !published {result.deinit();}} return __cleanup_result_6_0, __cleanup_result_6_1;}let paths,error=result.owner.copy(names.owners);if error!=blot_error::Error.none {let __cleanup_result_7_0: OwnedCore = OwnedCore{..}; let __cleanup_result_7_1: Error = error; {names.deinit();} {if !published {result.deinit();}} return __cleanup_result_7_0, __cleanup_result_7_1;}result.names=blot_backend_runtime_identity::Metadata{bytes,symbols,paths, ..};
 let order,error=result.owner.copy(source.order.items);if error!=blot_error::Error.none {let __cleanup_result_8_0: OwnedCore = OwnedCore{..}; let __cleanup_result_8_1: Error = error; {names.deinit();} {if !published {result.deinit();}} return __cleanup_result_8_0, __cleanup_result_8_1;}result.order=order;published=true;let __cleanup_result_9_0: OwnedCore = result; let __cleanup_result_9_1: Error = blot_error::Error.none; {names.deinit();} {if !published {result.deinit();}} return __cleanup_result_9_0, __cleanup_result_9_1;
 {names.deinit();} {if !published {result.deinit();}} }
