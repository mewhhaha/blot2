// One attempt owns actual-variant plans until all typed reference holders are empty.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace_backing;
import backend.resolved_body;
import backend.backend_emission;
import support.error;
fn inspectAndMutate(body:u32) {
    let stored .=blot_backend_resolved_body::getRef(body,3);
    match stored {static_binding &item=>{assert(item.value==17);item.value=23;},_=>{assert(false);}}
}
fn cycle() {
    let child,error=blot_backend_resolved_body::create(1,2,default<const blot_backend_layout::Mapping[:]>(),default<const blot_backend_layout::RowMapping[:]>());assert(error==blot_error::Error.none);
    assert(blot_backend_resolved_body::put(child,3,blot_backend_backend_emission::Plan.static_binding{value:17})==blot_error::Error.none);
    inspectAndMutate(child);
    match blot_backend_resolved_body::get(child,3) {static_binding item=>{assert(item.value==23);},_=>{assert(false);}}
    let parent,error=blot_backend_resolved_body::create(1,4,[default<blot_backend_layout::Mapping>()],[default<blot_backend_layout::RowMapping>()]);assert(error==blot_error::Error.none);
    let instances=blot_backend_backend_emission::owned_instances.alloc_slice(1);instances[0]=blot_backend_backend_emission::LocalInstance{layout:0,body:child};
    assert(blot_backend_resolved_body::put(parent,5,blot_backend_backend_emission::Plan.instances{value:instances})==blot_error::Error.none);
    blot_backend_resolved_body::setSink(parent,7,9);assert(blot_backend_resolved_body::entryCount(parent)==1 && blot_backend_resolved_body::sinkCount(parent)==1 && blot_backend_resolved_body::sink(parent,7).value==9);
    blot_backend_resolved_body::release(parent);assert(!blot_backend_resolved_body::headers[parent-1].active && !blot_backend_resolved_body::headers[child-1].active && !blot_backend_resolved_body::contains(child,3) && !blot_backend_resolved_body::contains(parent,5));
    blot_backend_resolved_body::deinit();assert(blot_backend_resolved_body::headers.len==0 && blot_backend_resolved_body::slots.len==0 && blot_backend_resolved_body::entries.count==0 && blot_backend_resolved_body::payloads.len==0);
    blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();
}
fn main() {for index in 0..4 {cycle();}print("resolved body passed: actual plans, mutation, recursive release, owned children and attempt reset");}
