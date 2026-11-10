// One attempt owns actual-variant plans until all typed reference holders are empty.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace_backing;
import backend.resolved_body;
import reuse.shared_query_gate;
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
fn publishInspection(target:blot_eval_completed_specialization_query::CachedPlan&) {
 var pools=default<blot_reuse_code_artifacts::Pools>();var gate=blot_reuse_principal_reuse_gate::Gate{..};let order=blot_reuse_source_value_template::plan_order.alloc_slice(2);order[0]=7;order[1]=11;
 let plan=blot_reuse_source_value_template::Plan{pools:pools,gate:gate,root:11,order:order,stats:blot_reuse_source_value_template::Stats{values:2,..},row_policy:blot_reuse_source_value_template::RowPolicy.source_declared};
 blot_eval_completed_specialization_query::publishCachedPlan(target,blot_support::Option<blot_reuse_source_value_template::Plan>{true,plan});
}
fn cacheOwnership(){let entries=blot_eval_completed_specialization_query::cached_plans.alloc_slice(1);entries[0]=blot_eval_completed_specialization_query::CachedPlan{source_admitted:blot_support::some(true),..};publishInspection(entries[0]);blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();assert(entries[0].has_plan && entries[0].root==11 && entries[0].order==[7 as u32,11 as u32] && entries[0].stats.values==2 && entries[0].row_policy==blot_reuse_source_value_template::RowPolicy.source_declared && entries[0].source_admitted.value);entries[0].deinit();blot_eval_completed_specialization_query::cached_plans.free_slice(entries);}
fn importPlanMetadata() {
 var map=blot_reuse_artifact_import::PlanMap{};
 {var pools=default<blot_reuse_code_artifacts::Pools>();var gate=blot_reuse_principal_reuse_gate::Gate{..};let order=blot_reuse_source_value_template::plan_order.alloc_slice(2);order[0]=7;order[1]=11;let plan=blot_reuse_source_value_template::Plan{pools:pools,gate:gate,root:11,order:order,stats:blot_reuse_source_value_template::Stats{values:2,..},row_policy:blot_reuse_source_value_template::RowPolicy.source_declared};map.insert(11,blot_reuse_source_value_template::metadata(plan));}
 blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();let cached .=map.get(11);assert(cached && cached.root==11 && cached.stats.values==2 && cached.order==[7 as u32,11 as u32]);
 var pools=default<blot_reuse_code_artifacts::Pools>();var gate=blot_reuse_principal_reuse_gate::Gate{..};let borrowed=cached.view(pools,gate);assert(borrowed.root==11 && borrowed.row_policy==blot_reuse_source_value_template::RowPolicy.source_declared);for &slot in map.table.slots {if slot.tag!=0 {slot.val.deinit();}}map.deinit();
}
// This adapter exercises only QueryScratch's binding protocol, not replay admission.
struct BindingEvaluator { allocation_owner:u64,owner_id:u64,units:const blot_check_core::Module[:]=default<const blot_check_core::Module[:]>() }
struct BindingGenerator { owner_id:u64,evaluator:BindingEvaluator }
reusable[] var bound_scratch:blot_reuse_source_value_template::QueryScratch[>..]=[];
fn scratchAuthority() {
 let allocation=blot_native::fresh_owner_id();var generator=BindingGenerator{blot_native::fresh_owner_id(),BindingEvaluator{allocation,blot_native::fresh_owner_id(),..}};
 var pools=default<blot_reuse_code_artifacts::Pools>();pools.generation=1;pools.evaluator.owner_id=blot_native::fresh_owner_id();
 var builder=blot_eval_pool_leases::Builder{};let children,error=blot_eval_pool_leases::alloc_children(builder,1);assert(error==blot_error::Error.none);children[0]=9;pools.leases=builder.leases;
 var gate,error=blot_reuse_principal_reuse_gate::init(allocation,pools,default<const blot_check_core::Module[:]>(),blot_support::none<blot_backend_runtime_identity::View>());assert(error==blot_error::Error.none);
 let units=default<const blot_check_core::Module[:]>();let names=blot_support::none<blot_backend_runtime_identity::View>();
 assert(!blot_reuse_shared_query_gate::share(allocation+1,pools,units,names,gate).present);
 var shared=blot_reuse_shared_query_gate::share(allocation,pools,units,names,gate);assert(shared.present && shared.value.live() && shared.value.storage==gate.storage && shared.value.source_pools .==pools);
 let scratch=bound_scratch.alloc_slice(1);scratch[0]=blot_reuse_source_value_template::QueryScratch{allocation_owner:allocation,..};
 let plan=blot_reuse_source_value_template::Plan{pools:pools,gate:gate,..};assert(scratch[0].bind(plan,generator)==blot_error::Error.none);
 let before=blot_native::clock_ns();for repeated in 0..10000 {assert(scratch[0].bind(plan,generator)==blot_error::Error.none);}print("scratch bind10000 ns ",blot_native::clock_ns()-before);
 // Different addresses with identical owned authority intentionally bind equally.
 var copy_pools=pools;var copy_gate=gate;let copied=blot_reuse_source_value_template::Plan{pools:copy_pools,gate:copy_gate,..};assert(scratch[0].bind(copied,generator)==blot_error::Error.none);
 copy_pools.generation++;assert(scratch[0].bind(copied,generator)==blot_error::Error.declined);copy_pools.generation=pools.generation;
 copy_pools.evaluator.owner_id=blot_native::fresh_owner_id();assert(scratch[0].bind(copied,generator)==blot_error::Error.declined);copy_pools.evaluator.owner_id=pools.evaluator.owner_id;
 let original_generator=generator.owner_id;generator.owner_id=blot_native::fresh_owner_id();assert(scratch[0].bind(plan,generator)==blot_error::Error.declined);generator.owner_id=original_generator;
 let original_session=generator.evaluator.owner_id;generator.evaluator.owner_id=blot_native::fresh_owner_id();assert(scratch[0].bind(plan,generator)==blot_error::Error.declined);generator.evaluator.owner_id=original_session;
 var other,error=blot_reuse_principal_reuse_gate::init(allocation,pools,default<const blot_check_core::Module[:]>(),blot_support::none<blot_backend_runtime_identity::View>());assert(error==blot_error::Error.none);let distinct=blot_reuse_source_value_template::Plan{pools:pools,gate:other,..};assert(scratch[0].bind(distinct,generator)==blot_error::Error.declined);other.deinit();
 let wrong_policy=blot_reuse_source_value_template::Plan{pools:pools,gate:gate,row_policy:blot_reuse_source_value_template::RowPolicy.source_declared,..};assert(scratch[0].bind(wrong_policy,generator)==blot_error::Error.declined);
 assert(blot_eval_pool_leases::release(builder.leases.values[11])==blot_error::Error.none);assert(scratch[0].bind(plan,generator)==blot_error::Error.declined);
 gate.deinit();assert(shared.value.live() && shared.value.offsets.len==1 && shared.value.offsets[0]==0);shared.value.deinit();assert(scratch[0].bind(copied,generator)==blot_error::Error.declined);scratch[0].deinit();bound_scratch.free_slice(scratch);
 blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();
}
fn main() {importPlanMetadata();scratchAuthority();cacheOwnership();for index in 0..4 {cycle();}print("resolved body passed: actual plans, mutation, recursive release, owned children and attempt reset");}
