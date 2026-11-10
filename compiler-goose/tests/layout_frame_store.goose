// Physical layout growth is checked through the real Frame and pinned Core input.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace;
import backend.core_backend;
import backend.layout;
import check.task_types;
import reuse.dependency_payload;
import support.native;
import support.error;
fn probe(frame:blot_compile_workspace::Frame,units:const blot_check_core::Module[:],pin:blot_reuse_dependency_payload::Owner)->blot_backend_result_publication::Owner,blot_check_effect_evidence::Handle {
 let workspace .=frame.borrow();assert(workspace);
 let owners=[pin];assert(blot_backend_core_backend::pinWorkspaceInputs(workspace,units,pin,owners[..],default<const blot_reuse_dependency_payload::Owner[:]>())==blot_error::Error.none);
 assert(workspace.generator.representations.init(workspace.compiled_units,workspace.publication_owner)==blot_error::Error.none);
 let service,error=blot_backend_core_backend::specializer(workspace.generator);assert(error==blot_error::Error.none);
 let handle,error=service.layouts.intern(blot_backend_layout::Tag.nominal,blot_check_task_types::handle.unit,blot_check_task_types::handle.decl,[]);assert(error==blot_error::Error.none && handle==7);
 let quantified,error=service.layouts.intern(blot_backend_layout::Tag.universal,blot_backend_layout::word,2,[]);assert(error==blot_error::Error.none);
 let children=service.layouts.children(quantified);assert(children.len==2);
 let stable_first=children[0];let stable_second=children[1];
 var element=quantified;for _ in 0..256 {let id,error=service.layouts.intern(blot_backend_layout::Tag.product,0,0,[element,blot_backend_layout::word]);assert(error==blot_error::Error.none && id!=0);element=id;}
 assert(children[0]==stable_first && children[1]==stable_second);
 let observed=service.layouts.children(quantified);assert(observed[0]==stable_first && observed[1]==stable_second);
 return workspace.publication_owner,service.layouts.effects;
}
fn main() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let names,error=owner.copy("physical-frame-layout");assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(owner,1);assert(error==blot_error::Error.none);units[0]=blot_check_core::Module{unit:1,names:names,..};
 var pin,error=owner.retain();assert(error==blot_error::Error.none);owner.deinit();
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);
 let publication,effects=probe(frame,units,pin);assert(frame.release()==blot_error::Error.none);assert(!effects.valid());let gone,missing=blot_backend_result_publication::registeredInputUnits(publication);assert(missing!=blot_error::Error.none);pin.deinit();
 print("layout Frame passed: pinned Core, normalization and retained children across growth");
}
