// Complete outcomes move owned proof runs; empty variants carry no owners.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.semantic_parallel;
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
fn main() {
 var values=blot_eval_semantic_parallel::Outcomes{};populate(values);assert(values.failure==blot_error::Error.none && values.len==6);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());assert(frame.release()==blot_error::Error.none);
 var completed:u32=0;for outcome,index in values.items {match outcome {complete item=>{assert(item.value.record.present && item.value.counts.independent_regions==17);var record=item.value.record.value;assert(record.depth==9 && record.sources[0].binding==2 && record.scalar_reads[0].target.binding==3);record.deinit();completed++;},out_of_memory=>{assert(index==0);},declined=>{assert(index==2);},cancelled=>{assert(index==4);},_=>{assert(false);},}}
 assert(completed==3);values.clear();values.push(Outcome.pending{});values.deinit();
}
