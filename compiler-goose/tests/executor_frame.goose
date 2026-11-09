import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import driver.project_executor;
import driver.compile_workspace;
import std;
import eval.selected_query;
import reuse.specialization_receipt;
import reuse.principal_query;
import backend.result_owner;
import reuse.frontend_binding_relocation;
fn bindingMap()->blot_reuse_frontend_binding_relocation::Map {
 let bindings=blot_reuse_frontend_binding_relocation::words(2,17);let nominals=blot_reuse_frontend_binding_relocation::words(2,23);let constructors=blot_reuse_frontend_binding_relocation::words(2,31);let contracts=blot_reuse_frontend_binding_relocation::words(2,41);let implementations=blot_reuse_frontend_binding_relocation::words(2,47);
 let qualifications=blot_reuse_frontend_binding_relocation::owned_qualifications.alloc_slice(1);qualifications[0]=blot_reuse_frontend_binding_relocation::Qualification{blot_parse_ast::Span{1,2},blot_parse_ast::Span{3,4}};
 return blot_reuse_frontend_binding_relocation::canonicalOwned(blot_reuse_frontend_binding_relocation::Map{bindings,nominals,constructors,contracts,implementations,qualifications});
}
fn mapPublication() {
 var result,error=blot_reuse_project_check::initResult();assert(error==blot_error::Error.none);assert(result.allocateReuse(1)==blot_error::Error.none);
 let mapping=bindingMap();result.binding_maps[0]=blot_support::Option<blot_reuse_frontend_binding_relocation::Map>{true,blot_reuse_frontend_binding_relocation::canonicalOwned(mapping)};
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 let observed=result.binding_maps[0];assert(observed.present && observed.value.binding(1).value==17);assert(observed.value.nominals[1]==23 && observed.value.constructors[1]==31 && observed.value.contracts[1]==41 && observed.value.implementations[1]==47);assert(observed.value.qualification(blot_parse_ast::Span{1,2})==blot_parse_ast::Span{3,4});
 result.deinit();
}
fn publishedTiming(owner:blot_backend_result_owner::Owner)->blot_backend_backend_timing::Stats {
 var name:u8[>..]=[];name.append("producer-label");var overflow:u8[>..]=[];overflow.append("overflow-producer");var stats=default<blot_backend_backend_timing::Stats>();
 stats.work.region_callers.entries[0]=blot_backend_backend_timing::RegionCost{caller:blot_backend_backend_timing::RegionCaller{name[..],7},regions:3,inclusive_us:13,solver_bytes:17,..};
 stats.work.region_callers.entries[1]=blot_backend_backend_timing::RegionCost{caller:blot_backend_backend_timing::RegionCaller{"overflow",11},regions:5,..};
 stats.work.region_callers.overflow=blot_backend_backend_timing::RegionCost{caller:blot_backend_backend_timing::RegionCaller{overflow[..],19},regions:23,..};
 let published,error=blot_backend_result_owner::ownedTiming(owner,stats);assert(error==blot_error::Error.none);name.clear();overflow.clear();return published;
}
fn timingPublication() {
 var owner,error=blot_backend_result_owner::init();assert(error==blot_error::Error.none);{let timing=publishedTiming(owner);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 assert(timing.work.region_callers.entries[0].caller.function=="producer-label" && timing.work.region_callers.entries[0].caller.line==7 && timing.work.region_callers.entries[0].regions==3 && timing.work.region_callers.entries[0].inclusive_us==13 && timing.work.region_callers.entries[0].solver_bytes==17);
 assert(timing.work.region_callers.entries[1].caller.function=="overflow" && timing.work.region_callers.entries[1].regions==5 && timing.work.region_callers.entries[2].caller.function.len==0);
 assert(timing.work.region_callers.overflow.caller.function=="overflow-producer" && timing.work.region_callers.overflow.regions==23);
 assert(blot_backend_result_owner::get(owner).timing_names.len=="producer-label".len+"overflow-producer".len);}
 let start:i64={let entry .= blot_backend_result_owner::get(owner);let owned=blot_backend_result_owner::byte_runs.realloc_slice(entry.timing_names.storage,entry.timing_names.storage.len);assert(blot_support::same_slice_identity(owned,entry.timing_names.storage));let index=blot_backend_result_owner::byte_runs.index_of(owned[0]);entry.timing_names.items=default<u8[:]>();entry.timing_names.len=0;index};
 let capacity=blot_backend_result_owner::get(owner).timing_names.storage.len;let repeated=publishedTiming(owner);assert(repeated.work.region_callers.entries[0].caller.function=="producer-label");
 {let entry .= blot_backend_result_owner::get(owner);let owned=blot_backend_result_owner::byte_runs.realloc_slice(entry.timing_names.storage,entry.timing_names.storage.len);assert(blot_support::same_slice_identity(owned,entry.timing_names.storage));assert(entry.timing_names.storage.len==capacity && blot_backend_result_owner::byte_runs.index_of(owned[0])==start);}
 let old=owner;owner.deinit();assert(!blot_backend_result_owner::valid(old));
}
// This exercises typed table metadata ownership, not principal-proof admission.
fn queryPublication() {
 var table=blot_reuse_principal_query::init(blot_reuse_semantic_query_table::Limits{records:20,..});
 for index in 0..20 {
  var builder=table.begin(blot_reuse_principal_query::Key{blot_check_core::BindingRef{1,1},blot_eval_core_eval::Options{..}});
  builder.read(blot_reuse_principal_query::Dependencies{..});builder.stage(blot_eval_core_eval::SolvedEvidence{types:blot_eval_core_eval::copySolvedTypes([blot_eval_type_evidence::Mapping{(index+1) as u32,17}]),rows:blot_eval_core_eval::copySolvedRows([blot_eval_type_evidence::RowMapping{(index+1) as u32,23}]),..});
  var candidate=builder.complete();builder.abort();assert(candidate.present);let prepared,error=table.prepare(candidate.value);assert(error==blot_error::Error.none && prepared.present);let handle=table.publish(prepared.value,candidate.value);assert(handle.position==index);candidate.value.abort();
 }
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 assert(table.storage().records==20);
 for index in 0..20 {let record=table.get(blot_reuse_semantic_query_table::Handle<blot_reuse_principal_query::Adapter>{index as u32,table.owner});assert(record && record.value.types[0].variable==index+1 && record.value.types[0].evidence==17 && record.value.rows[0].evidence==23);}
 let fingerprint=blot_reuse_principal_query::fingerprint(blot_check_core::BindingRef{1,1});var cursor=table.candidates(fingerprint,blot_reuse_semantic_query_table::Order.oldest_first);for index in 0..20 {let found=cursor.next();assert(found.present && found.value==index);}assert(!cursor.next().present);
 var newest=table.candidates(fingerprint,blot_reuse_semantic_query_table::Order.newest_first);assert(newest.next().value==19);
 table.deinit();
}
fn ownedSelectedReceipt()->blot_reuse_specialization_receipt::Record {
 let target=blot_check_core::BindingRef{1,3};let member=blot_reuse_specialization_receipt::Member{ready:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::ReadyRead{target,7}]),principals:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::PrincipalRead{target,true,false,false,blot_reuse_specialization_receipt::PrincipalOutcome.graph}]),target:target,function:11,query_budgets:[1 as i64;8],..};
 return blot_reuse_specialization_receipt::canonicalOwned(blot_reuse_specialization_receipt::Record{member:blot_support::Option<blot_reuse_specialization_receipt::Member>{true,member},completed_closures:blot_reuse_specialization_receipt::copyOwned([13 as u32]),input:17,expected:19,selected:23,options:blot_eval_core_eval::Options{..},depth:29,values_before:31,children_before:37,values_added:41,children_added:43,steps:0,collected:47,source_scopes:53,solver_nodes:59,complete:true,sources:blot_reuse_specialization_receipt::copyOwned([target]),scalar_reads:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::ScalarRead{target,61}]),call_reads:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::CallRead{1,3,67,true}]),call_publications:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::CallRead{1,3,71,true}]),views:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::ViewEffect{73,79,83,true}]),plain_facts:blot_reuse_specialization_receipt::copyOwned([blot_reuse_specialization_receipt::PlainFact{89,true,..}])});
}
fn selectedReceiptPublication() {
 var source=ownedSelectedReceipt();let cloned,error=source.clone();assert(error==blot_error::Error.none);source.deinit();
 let adapter=blot_eval_selected_query::Adapter{};let slots,error=adapter.allocateRecords(1);assert(error==blot_error::Error.none);
 let record=blot_eval_selected_query::Record{key:blot_eval_selected_query::Key{blot_eval_selected_query::memberSource(cloned.member.value.target),cloned.input,cloned.expected,cloned.options,cloned.depth},dependencies:cloned,value:blot_eval_selected_query::Result{cloned.selected}};assert(adapter.complete(record));adapter.storeRecord(slots,0,record);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 let proof=slots[0].dependencies;assert(proof.member.present && proof.member.value.ready[0].value==7 && proof.member.value.principals[0].outcome==blot_reuse_specialization_receipt::PrincipalOutcome.graph && proof.member.value.query_budgets[7]==1);
 assert(proof.completed_closures[0]==13 && proof.sources[0].binding==3 && proof.scalar_reads[0].evidence==61 && proof.call_reads[0].evidence==67 && proof.call_publications[0].evidence==71 && proof.views[0].selected==83 && proof.plain_facts[0].key==89);
 assert(proof.input==17 && proof.expected==19 && proof.selected==23 && proof.depth==29 && proof.values_before==31 && proof.children_before==37 && proof.values_added==41 && proof.children_added==43 && proof.collected==47 && proof.source_scopes==53 && proof.solver_nodes==59 && proof.complete);
 slots[0].deinit();adapter.releaseRecords(slots);
}
fn main() {
 selectedReceiptPublication();
 queryPublication();
 timingPublication();
 mapPublication();
 var worker=blot_project_executor::init();let source=blot_reuse_project::Project{};
 var engine,error=blot_reuse_project_check::initEngine(source,blot_check_check::PrivateExecution{},blot_reuse_project_check::Editor.none,false);assert(error==blot_error::Error.none);
 let order:u32[0]=default<u32[0]>();let jobs=blot_reuse_project_check::project_jobs.alloc_slice(1);jobs[0]=blot_reuse_project_check::ParallelJob{};
 let rejected,error=worker.runProjectChecks(engine,order[..],1,jobs);assert(error==blot_error::Error.invalid_request);
 let counts,error=worker.runProjectChecks(engine,order[..],1,jobs[..0]);assert(error==blot_error::Error.none);engine.deinit();worker.deinit();
 for &job in jobs {job.deinit();}blot_reuse_project_check::project_jobs.free_slice(jobs);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 print("executor Frame ownership passed: invalid-size rejection, valid empty batch and pooled-slot cleanup");
}
