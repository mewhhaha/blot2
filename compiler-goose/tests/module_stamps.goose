// Exact memo entries snapshot headers; source-owner keys only reborrow the header.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.code_artifacts;
import backend.result_publication;
import reuse.dependency_payload;
import reuse.dependency_identity;
import reuse.source_completion;
import reuse.dependency_stamp_view;
var module_text:u8[4]=[117,110,105,116];
var previous_module:blot_check_core::Module=blot_check_core::Module{unit:1,names:module_text[..],..};
fn registeredStampLeafViews() {
 var catalog,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let names,error=catalog.copy("registered-leaf-module");assert(error==blot_error::Error.none);
 let selected,error=catalog.copy([11 as u32,22 as u32,33 as u32,44 as u32]);assert(error==blot_error::Error.none);
 let modules,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(catalog,1);assert(error==blot_error::Error.none);
 modules[0]=blot_check_core::Module{unit:1,names:names,selected_edges:selected,..};
 let expected=blot_check_core::stampView(modules[0]);let units=catalog.mutable(modules);
 var retained,error=catalog.retain();assert(error==blot_error::Error.none && !retained.unique());
 var publication,error=blot_backend_result_publication::init(blot_native::fresh_owner_id(),blot_native::fresh_owner_id());assert(error==blot_error::Error.none);
 let owners:blot_reuse_dependency_payload::Owner[1]=[catalog];assert(blot_backend_result_publication::stageInputs(publication,units,catalog,owners[..],default<const blot_reuse_dependency_payload::Owner[:]>())==blot_error::Error.none);
 catalog.deinit();
 let registered,error=blot_backend_result_publication::registeredInputUnits(publication);assert(error==blot_error::Error.none && registered.len==1);
 let observed=blot_backend_result_publication::registeredInputHeader(publication,0);assert(observed==expected);
 let full=blot_backend_result_publication::registeredStampSlice(publication,selected);
 assert(blot_support::same_slice_identity(full,selected) && full.len==4 && full[0]==11 && full[3]==44);
 let name_full=blot_backend_result_publication::registeredStampSlice(publication,names);
 assert(blot_support::same_slice_identity(name_full,names) && name_full.len==names.len && name_full[0]=='r' && name_full[1]=='e');
 let name_prefix=blot_backend_result_publication::registeredStampSlice(publication,names[..5]);
 assert(blot_support::same_slice_identity(name_prefix,names[..5]) && name_prefix.len==5 && name_prefix[4]=='s');
 let name_interior=blot_backend_result_publication::registeredStampSlice(publication,names[2..7]);
 assert(blot_support::same_slice_identity(name_interior,names[2..7]) && name_interior.len==5 && name_interior[0]=='g' && name_interior[4]=='e');
 assert(blot_support::same_slice_identity(blot_backend_result_publication::registeredStampSlice(publication,names),names) && names[0]=='r');
 let prefix=blot_backend_result_publication::registeredStampSlice(publication,selected[..3]);
 assert(blot_support::same_slice_identity(prefix,selected[..3]) && prefix.len==3 && prefix[2]==33);
 let interior=blot_backend_result_publication::registeredStampSlice(publication,selected[1..3]);
 assert(blot_support::same_slice_identity(interior,selected[1..3]) && interior.len==2 && interior[0]==22 && interior[1]==33);
 assert(blot_support::same_slice_identity(blot_backend_result_publication::registeredStampSlice(publication,selected),selected));
 let writable=blot_backend_result_publication::module_runs.realloc_slice(registered,registered.len);assert(blot_support::same_slice_identity(writable,registered));
 writable[0].has_numeric_proofs=true;assert(!observed.has_numeric_proofs && !expected.has_numeric_proofs);
 assert(blot_backend_result_publication::registeredInputHeader(publication,0).has_numeric_proofs);
 assert(blot_support::same_slice_identity(blot_backend_result_publication::registeredStampSlice(publication,selected),selected) && selected[0]==11 && selected[3]==44);
 assert(blot_backend_result_publication::destroy(publication)==blot_error::Error.none);
 assert(selected[0]==11 && selected[1]==22 && selected[2]==33 && selected[3]==44);
 retained.deinit();
}

fn registeredCatalogInputViews() {
 var catalog,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 var first=default<u8[32]>();first[0]=7;first[31]=17;
 var second=default<u8[32]>();second[0]=23;second[31]=41;
 let digests,error=catalog.copy([first,second]);assert(error==blot_error::Error.none);
 let order,error=catalog.copy([3 as u32,1 as u32,2 as u32]);assert(error==blot_error::Error.none);
 var retained,error=catalog.retain();assert(error==blot_error::Error.none && !catalog.unique() && !retained.unique());
 let before_digests=blot_reuse_dependency_payload::registeredCatalogDigests(catalog,digests);
 let before_order=blot_reuse_dependency_payload::registeredCatalogOrder(catalog,order);
 assert(blot_support::same_slice_identity(before_digests,digests) && before_digests.len==2);
 assert(before_digests[0][0]==7 && before_digests[0][31]==17 && before_digests[1][0]==23 && before_digests[1][31]==41);
 assert(blot_support::same_slice_identity(before_order,order) && before_order.len==3 && before_order[0]==3 && before_order[1]==1 && before_order[2]==2);
 catalog.deinit();assert(retained.valid());
 let after_digests=blot_reuse_dependency_payload::registeredCatalogDigests(retained,digests);
 let after_order=blot_reuse_dependency_payload::registeredCatalogOrder(retained,order);
 assert(blot_support::same_slice_identity(after_digests,before_digests) && after_digests.len==2);
 assert(after_digests[0][0]==7 && after_digests[0][31]==17 && after_digests[1][0]==23 && after_digests[1][31]==41);
 assert(blot_support::same_slice_identity(after_order,before_order) && after_order.len==3 && after_order[0]==3 && after_order[1]==1 && after_order[2]==2);
 assert(blot_reuse_dependency_payload::registeredCatalogDigests(retained,default<const u8[32][:]>()).len==0);
 assert(blot_reuse_dependency_payload::registeredCatalogOrder(retained,default<const u32[:]>()).len==0);
 retained.deinit();
}

fn scalarSourceReceiptBorrow() {
 assert(blot_reuse_source_completion::prefixValue(null).slot==0 && blot_reuse_source_completion::entryValue(null).slot==0);
 let p=blot_reuse_source_completion::prefixes.alloc_index(blot_reuse_source_completion::PrefixState{generation:11,live:true,..});
 blot_reuse_source_completion::prefixes[p].canonical=blot_reuse_source_completion::Prefix{(p+1) as u32,11};
 let e=blot_reuse_source_completion::entries.alloc_index(blot_reuse_source_completion::EntryState{generation:21,live:true,..});
 blot_reuse_source_completion::entries[e].canonical=blot_reuse_source_completion::Entry{(e+1) as u32,21};
 let borrowed=blot_reuse_source_completion::Borrow{prefix:blot_reuse_source_completion::prefixValue(blot_reuse_source_completion::prefixes[p].canonical),entry:blot_reuse_source_completion::entryValue(blot_reuse_source_completion::entries[e].canonical)};
 assert(borrowed.prefix.valid() && borrowed.entry.valid());
 blot_reuse_source_completion::prefixes[p].canonical.deinit();blot_reuse_source_completion::entries[e].canonical.deinit();
 assert(!borrowed.prefix.valid() && !borrowed.entry.valid());
 let next_p=blot_reuse_source_completion::prefixes.alloc_index(blot_reuse_source_completion::PrefixState{generation:12,live:true,..});
 blot_reuse_source_completion::prefixes[next_p].canonical=blot_reuse_source_completion::Prefix{(next_p+1) as u32,12};
 let next_e=blot_reuse_source_completion::entries.alloc_index(blot_reuse_source_completion::EntryState{generation:22,live:true,..});
 blot_reuse_source_completion::entries[next_e].canonical=blot_reuse_source_completion::Entry{(next_e+1) as u32,22};
 assert(!borrowed.prefix.valid() && !borrowed.entry.valid());
 blot_reuse_source_completion::prefixes[next_p].canonical.deinit();blot_reuse_source_completion::entries[next_e].canonical.deinit();
}

fn main() {
 scalarSourceReceiptBorrow();
 registeredCatalogInputViews();
 registeredStampLeafViews();
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
