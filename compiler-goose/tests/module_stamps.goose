// Exact memo entries snapshot headers; source-owner keys only reborrow the header.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.code_artifacts;
import backend.result_publication;
import reuse.dependency_payload;
var module_text:u8[4]=[117,110,105,116];
var previous_module:blot_check_core::Module=blot_check_core::Module{unit:1,names:module_text[..],..};
fn main() {
 var catalog,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let source,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(catalog,1);assert(error==blot_error::Error.none);
 source[0]=blot_check_core::Module{unit:1,names:module_text[..],..};
 var publication,error=blot_backend_result_publication::init(blot_native::fresh_owner_id(),blot_native::fresh_owner_id());assert(error==blot_error::Error.none);
 let owners:blot_reuse_dependency_payload::Owner[1]=[catalog];assert(blot_backend_result_publication::stageInputs(publication,source,catalog,owners[..],default<const blot_reuse_dependency_payload::Owner[:]>())==blot_error::Error.none);
 let current,error=blot_backend_result_publication::registeredInputUnits(publication);assert(error==blot_error::Error.none);catalog.deinit();
 let pins=blot_reuse_code_artifacts::allocateOwned_pins(1);pins[0]=blot_reuse_code_artifacts::init(1,previous_module,blot_reuse_code_artifacts::copyOwned("/unit.blot"));
 let created,error=blot_reuse_code_artifacts::initPooledRef();assert(error==blot_error::Error.none&&created!=null);let context:blot_reuse_code_artifacts::Context& =created;context.pools=blot_support::Option<blot_reuse_code_artifacts::Pools>{true,blot_reuse_code_artifacts::Pools{modules:pins,..}};
 var stamp_entries:blot_reuse_code_artifacts::ModuleStampEntry[>..<]=[];var memo=blot_reuse_code_artifacts::ModuleStamps{storage:stamp_entries,compare_contents:true,validate:true,..};assert(memo.bindSources(publication,current,context)==blot_error::Error.none);assert(stamp_entries.len==0);assert(memo.bindSources(publication,current,context)==blot_error::Error.invalid_artifact && stamp_entries.len==0);assert(memo.owns(current[0])&&memo.owns(previous_module));
 var other_entries:blot_reuse_code_artifacts::ModuleStampEntry[>..<]=[];var other=blot_reuse_code_artifacts::ModuleStamps{storage:other_entries,..};assert(other.bindSources(publication,current,null)==blot_error::Error.none);let separate,error=other.get(current[0]);assert(error==blot_error::Error.none&&other_entries.len==1&&stamp_entries.len==0);other.deinit();assert(other_entries.len==0&&memo.bound);
 let old,error=memo.get(previous_module);assert(error==blot_error::Error.none&&old==pins[0].token);let token,error=memo.get(current[0]);assert(error==blot_error::Error.none&&token==old);
 assert(memo.entries().len==1&&!memo.entries()[0].module.has_numeric_proofs);
 let writable=blot_backend_result_publication::module_runs.realloc_slice(current,current.len);writable[0].has_numeric_proofs=true;
 assert(!memo.entries()[0].module.has_numeric_proofs);let changed,error=memo.get(current[0]);assert(error==blot_error::Error.none&&changed!=token&&memo.entries().len==2);assert(memo.entries()[1].module.has_numeric_proofs);
 let repeated,error=memo.get(current[0]);assert(error==blot_error::Error.none&&repeated==changed);
 assert(memo.entries()[0].module.names=="unit"&&!memo.entries()[0].module.has_numeric_proofs&&memo.entries()[1].module.has_numeric_proofs);
 // Header-snapshot law: memo scratch ends before its published sources.
 memo.deinit();memo.deinit();assert(stamp_entries.len==0 && !memo.bound && memo.current_owner.slot==0 && memo.previous_context==0);
 assert(memo.bindSources(blot_backend_result_publication::Owner{},current,context)==blot_error::Error.invalid_artifact && stamp_entries.len==0);
 assert(current[0].names=="unit"&&current[0].has_numeric_proofs&&!previous_module.has_numeric_proofs);context.releasePooled();assert(blot_backend_result_publication::destroy(publication)==blot_error::Error.none);
 print("module stamp source owners passed");
}
