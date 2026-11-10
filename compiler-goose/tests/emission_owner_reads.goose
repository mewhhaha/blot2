// Executed authority boundaries; this law does not execute Core or prepareMapped.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.backend_emission;
import backend.substitution_buffers;
import backend.resolved_body;
import driver.compile_workspace;
import support.error;
import support.native;
type Mapping=blot_backend_layout::Mapping;
type RowMapping=blot_backend_layout::RowMapping;
type Maps=blot_backend_substitution_buffers::Mappings;
type Rows=blot_backend_substitution_buffers::Rows;
type Owner=blot_backend_backend_emission::Owner;
fn bufferReads() {
 var maps=Maps{};var rows=Rows{};
 assert(blot_backend_backend_emission::bufferMappings(maps).valid());
 assert(maps.push(Mapping{variable:7,layout:blot_backend_layout::word,..})==blot_error::Error.none);
 assert(maps.push(Mapping{variable:11,layout:2,..})==blot_error::Error.none);
 assert(rows.push(RowMapping{variable:17,row:19})==blot_error::Error.none);
 let selected=blot_backend_backend_emission::bufferMappings(maps);let row_selected=blot_backend_backend_emission::bufferRows(rows);
 assert(selected.valid() && row_selected.valid() && blot_backend_backend_emission::readMappings(selected)[1].variable==11);
 assert(blot_support::same_slice_identity(blot_backend_backend_emission::readMappings(selected),maps.items));
 var inner=selected.buffer;inner.offset=1;inner.len=1;assert(inner.valid() && blot_backend_substitution_buffers::read(inner)[0].layout==2);
 for index in 0..256 {assert(maps.push(Mapping{variable:(index+23) as u32,layout:blot_backend_layout::word,..})==blot_error::Error.none);}
 assert(selected.valid() && blot_backend_backend_emission::readMappings(selected).len==2 && blot_support::same_slice_identity(blot_backend_backend_emission::readMappings(selected),maps.items[..2]));
 var invalid=inner;invalid.offset=maps.items.len;assert(!invalid.valid());invalid=inner;invalid.owner_id=0;assert(!invalid.valid());invalid=inner;invalid.len=-1;assert(!invalid.valid());
 let lease=maps.lease;maps.deinit();assert(!selected.valid() && !inner.valid());
 assert(maps.push(Mapping{variable:41,layout:blot_backend_layout::word,..})==blot_error::Error.none);assert(maps.lease==lease && !selected.valid());maps.deinit();
 let old_rows=row_selected;var taken_rows=blot_backend_backend_emission::takeRows(rows);assert(rows.lease==0 && taken_rows.valid() && old_rows.valid());rows.deinit();assert(taken_rows.valid());blot_backend_substitution_buffers::release(taken_rows.buffer);assert(!old_rows.valid());
 assert(blot_backend_substitution_buffers::prepare(maps)==blot_error::Error.none);let empty=blot_backend_backend_emission::bufferMappings(maps);assert(empty.len==0 && empty.buffer.lease!=0 && empty.valid());var taken=blot_backend_backend_emission::takeMappings(maps);assert(maps.lease==0 && taken.valid());maps.deinit();assert(empty.valid());blot_backend_substitution_buffers::release(taken.buffer);assert(!empty.valid());
}
fn bodyReads() {
 let body,error=blot_backend_resolved_body::create(1,2,[Mapping{variable:7,layout:blot_backend_layout::word,..}],[RowMapping{variable:17,row:19}]);assert(error==blot_error::Error.none);
 let maps=blot_backend_backend_emission::bodyMappings(body);let rows=blot_backend_backend_emission::bodyRows(body);assert(maps.valid() && rows.valid() && blot_backend_backend_emission::readMappings(maps)[0].variable==7 && blot_backend_backend_emission::readRows(rows)[0].row==19);
 var invalid=maps;invalid.owner_id=0;assert(!invalid.valid());invalid=maps;invalid.offset=1;assert(!invalid.valid());
 blot_backend_resolved_body::release(body);assert(!maps.valid() && !rows.valid());blot_backend_resolved_body::deinit();
 let replacement,error=blot_backend_resolved_body::create(1,2,default<const Mapping[:]>(),default<const RowMapping[:]>());assert(error==blot_error::Error.none && replacement==body && !maps.valid());blot_backend_resolved_body::release(replacement);blot_backend_resolved_body::deinit();
}
fn instanceReads() {
 var decisions=blot_backend_backend_emission::InstanceDecisions{..};
 let empty,error=blot_backend_backend_emission::snapshotInstances(decisions);assert(error==blot_error::Error.none && empty.valid() && empty.len==0 && decisions.facts.lease==0);
 var decision=blot_backend_backend_emission::InstanceDecision{statement:9,count:1,reads:blot_backend_backend_emission::InstanceReads{nodes:default<u32[32]>(),len:1},..};decision.reads.nodes[0]=31;
 assert(decisions.decisions.push(decision)==blot_error::Error.none);
 let no_facts,error=blot_backend_backend_emission::snapshotInstances(decisions);assert(error==blot_error::Error.none && no_facts.valid() && no_facts.facts.lease!=0 && no_facts.facts.len==0 && no_facts.rows.lease==0);
 {let found .=no_facts.find(9);assert(found);assert(found.count==1 && no_facts.factsAt(found,0).len==0 && no_facts.rowsAt(found,0).len==0);}
 assert(no_facts.find(10)==null);decisions.deinit();assert(!no_facts.valid());
 assert(decisions.facts.push(Mapping{variable:7,layout:blot_backend_layout::word,..})==blot_error::Error.none);assert(decisions.rows.push(RowMapping{variable:17,row:19})==blot_error::Error.none);
 decision.facts[0]=blot_backend_backend_emission::FactRange{start:0,len:1};decision.rows[0]=blot_backend_backend_emission::FactRange{start:0,len:1};assert(decisions.decisions.push(decision)==blot_error::Error.none);
 let populated,error=blot_backend_backend_emission::snapshotInstances(decisions);assert(error==blot_error::Error.none && populated.valid() && !no_facts.valid());
 {let found .=populated.find(9);assert(found);assert(populated.factsAt(found,0)[0].variable==7 && populated.rowsAt(found,0)[0].row==19);}
 decisions.deinit();assert(!populated.valid() && !no_facts.valid());
}
recursive fn nested(owner:Owner&,depth:i64) {
 assert(owner.generator() .==blot_compile_workspace::generatorForFrame(owner.frame));assert(owner.mappings()[0].variable==7 && owner.row_mappings()[0].row==19);
 if depth==0 {return;}
 var child=Owner{frame:owner.frame,unit_id:1,function_id:0,mapping_read:owner.mapping_read,row_read:owner.row_read,..};nested(child,depth-1);child.deinit();
 assert(owner.mappings()[0].variable==7 && owner.row_mappings()[0].row==19);
}
fn frameReads() {
 var maps=Maps{};var rows=Rows{};assert(maps.push(Mapping{variable:7,layout:blot_backend_layout::word,..})==blot_error::Error.none && rows.push(RowMapping{variable:17,row:19})==blot_error::Error.none);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);
 var owner=Owner{frame:frame,unit_id:1,function_id:0,mapping_read:blot_backend_backend_emission::bufferMappings(maps),row_read:blot_backend_backend_emission::bufferRows(rows),..};nested(owner,2);owner.deinit();assert(frame.release()==blot_error::Error.none && !frame.valid());maps.deinit();rows.deinit();
}
fn main() {bufferReads();bodyReads();instanceReads();frameReads();print("emission owner reads passed: exact named owners, ranges, lease transfer, nested scalar owners and release/reuse rejection");}
