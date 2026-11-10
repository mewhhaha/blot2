// Complete outcomes move owned proof runs; empty variants carry no owners.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.semantic_parallel;
import eval.component_worker;
import support.evidence_packet;
import driver.compile_workspace;
type Outcome=blot_eval_semantic_job_batch::Outcome<blot_eval_semantic_parallel::Result>;
fn ownedRecord()->blot_reuse_independent_call_proof::Record {
 let sources=[blot_check_core::BindingRef{1,2}];let scalars=[blot_reuse_independent_call_proof::ScalarInput{target:blot_check_core::BindingRef{1,3},evidence:4,value:blot_support::none<blot_eval_core_eval::Value>()}];
 return blot_reuse_independent_call_proof::Record{target:blot_check_core::BindingRef{1,7},evidence:3,options:blot_eval_core_eval::Options{},depth:9,sources:blot_reuse_independent_call_proof::copySources(sources),scalar_reads:blot_reuse_independent_call_proof::copyScalars(scalars)};
}
fn complete()->Outcome {return Outcome.complete{blot_eval_semantic_parallel::Result{record:blot_support::Option<blot_reuse_independent_call_proof::Record>{true,ownedRecord()},counts:blot_eval_semantic_parallel::Counts{independent_regions:17,..}}};}
fn populate(values:blot_eval_semantic_parallel::Outcomes&) {
 values.push(Outcome.out_of_memory{});values.push(complete());let extra:Outcome[3]=[Outcome.declined{},complete(),Outcome.cancelled{}];values.append(extra);values.resize(6,complete());
}
type ComponentOutcome=blot_eval_semantic_job_batch::Outcome<blot_eval_component_worker::Result>;
fn componentComplete()->ComponentOutcome {
 var source,error=blot_eval_type_evidence::init();assert(error==blot_error::Error.none);let root,error=source.intern(blot_eval_type_evidence::Tag.array,3,0,[]);assert(error==blot_error::Error.none);
 var bytes:u8[>..<]=[];assert(blot_evidence_packet::encode(source.view(),bytes)==blot_error::Error.none);source.deinit();let packet=blot_reuse_code_artifacts::copyOwned(bytes[..]);let snapshot,error=blot_evidence_packet::decode(packet);blot_reuse_code_artifacts::releaseOwned(packet);assert(error==blot_error::Error.none);
 let keys=blot_eval_component_worker::result_keys.alloc_slice(1);keys[0]=blot_eval_core_eval::CallSummaryKey{..};let roots=blot_eval_component_worker::result_roots.alloc_slice(1);roots[0]=root;let sources=blot_eval_component_worker::result_sources.alloc_slice(1);sources[0]=blot_check_core::BindingRef{1,7};
 return ComponentOutcome.complete{blot_eval_component_worker::Result{snapshot:blot_support::Option<blot_evidence_packet::OwnedSnapshot>{true,snapshot},keys:keys,roots:roots,sources:sources,recursive_members:2,restarts:3,transitions:5,job_nanos:11,..}};
}
fn componentPopulate(values:blot_eval_core_eval::CoreComponentOutcomesBuffer&) {values.push(ComponentOutcome.out_of_memory{});values.push(componentComplete());let extra:ComponentOutcome[3]=[ComponentOutcome.declined{},componentComplete(),ComponentOutcome.cancelled{}];values.append(extra);values.resize(6,componentComplete());}
fn componentOutcomes() {
 var values=blot_eval_core_eval::CoreComponentOutcomesBuffer{};componentPopulate(values);assert(values.failure==blot_error::Error.none && values.len==6);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);
 var completed:u32=0;for outcome,index in values.items {match outcome {complete item=>{var result=item.value;assert(result.snapshot.present && result.keys.len==1 && result.sources[0].binding==7 && result.recursive_members==2 && result.restarts==3 && result.transitions==5 && result.job_nanos==11);let key=result.snapshot.value;assert(blot_evidence_packet::valid(key));let node=key.snapshot.nodes[result.roots[0]];assert(node.tag==blot_eval_type_evidence::Tag.array && node.a==3);result.deinit();assert(!blot_evidence_packet::valid(key));completed++;},out_of_memory=>{assert(index==0);},declined=>{assert(index==2);},cancelled=>{assert(index==4);},_=>{assert(false);},}}
 assert(completed==3);values.clear();values.push(ComponentOutcome.pending{});values.deinit();
}
fn main() {
 componentOutcomes();
 var values=blot_eval_semantic_parallel::Outcomes{};populate(values);assert(values.failure==blot_error::Error.none && values.len==6);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());assert(frame.release()==blot_error::Error.none);
 var completed:u32=0;for outcome,index in values.items {match outcome {complete item=>{assert(item.value.record.present && item.value.counts.independent_regions==17);var record=item.value.record.value;assert(record.depth==9 && record.sources[0].binding==2 && record.scalar_reads[0].target.binding==3);record.deinit();completed++;},out_of_memory=>{assert(index==0);},declined=>{assert(index==2);},cancelled=>{assert(index==4);},_=>{assert(false);},}}
 assert(completed==3);values.clear();values.push(Outcome.pending{});values.deinit();
}
