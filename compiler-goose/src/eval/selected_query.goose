namespace blot_eval_selected_query;
import check.core;
import eval.core_eval;
import eval.eval_values;
import reuse.semantic_query_table;
import reuse.specialization_receipt;
import support.error;
import support.host_layout;
import support.wyhash;
import support.structural;
import support.structural_adapters;

import support.option;
type Error=blot_error::Error;
struct Source { unit: u32,identity: u32,origin: blot_eval_eval_values::ClosureOrigin,applied: u32,member: bool=false }
fn source(value: blot_eval_eval_values::ClosureValue) -> Source { return Source {value.unit,value.identity,value.origin,value.applied,false}; }
fn memberSource(target: blot_check_core::BindingRef) -> Source { return Source {target.unit,target.binding,blot_eval_eval_values::ClosureOrigin.named,0,true}; }
fn fingerprint(value: Source,options: blot_eval_core_eval::Options,depth: i64) -> u64 {
 var hash=blot_support_wyhash::init(0); hash.value(value.unit); hash.value(value.identity); hash.value(blot_eval_eval_values::closureOriginCode(value.origin)); hash.value(value.applied); hash.value(value.member); blot_structural::hash(hash,options); blot_structural::hash(hash,depth); return hash.final();
}
struct Key { source: Source,input: u32,expected: u32,options: blot_eval_core_eval::Options,depth: i64 }
fn deinit(self_: Key&) {}
struct Result { selected: u32 }
fn deinit(self_: Result&) {}
struct Adapter {}
type Record=blot_reuse_semantic_query_table::OwnedRecord<Key,blot_reuse_specialization_receipt::Record,Result,Adapter>;
type Table=blot_reuse_semantic_query_table::Table<Key,blot_reuse_specialization_receipt::Record,Result,Adapter>;
reusable[] var records: Record[>..]=[];
fn fingerprint(self_: Adapter,key: Key) -> u64 { return fingerprint(key.source,key.options,key.depth); }
fn complete(self_: Adapter,record: Record) -> bool {
 let proof=record.dependencies;
 if proof.member.present { if memberSource(proof.member.value.target)!=record.key.source { return false; } } else if record.key.source.member { return false; }
 return proof.complete&&proof.steps==0&&proof.input==record.key.input&&proof.expected==record.key.expected&&proof.selected==record.value.selected&&proof.depth==record.key.depth&&proof.options==record.key.options;
}
fn bytes(self_: Adapter,record: Record) -> i64 { return blot_reuse_specialization_receipt::ownedBytes(record.dependencies); }
fn allocateRecords(self_: Adapter,len: i64) -> Record[:],Error { return records.alloc_slice(len),blot_error::Error.none; }
fn releaseRecords(self_: Adapter,values: const Record[:]) { if values.len==0 { return; } records.free_slice(values); }
fn recordBytes(self_: Adapter) -> i64 { return blot_host_layout::selected_query_record; }
fn init() -> Table { return blot_reuse_semantic_query_table::init<Key,blot_reuse_specialization_receipt::Record,Result,Adapter>(Adapter {}); }
fn remember(table: Table&,closure: blot_eval_eval_values::ClosureValue,owned: blot_reuse_specialization_receipt::Record) -> u32,bool,Error {
 var origin=source(closure); if owned.member.present { origin=memberSource(owned.member.value.target); }
 var builder=table.begin(Key {origin,owned.input,owned.expected,owned.options,owned.depth}); builder.read(owned); builder.stage(Result {owned.selected});
 var candidate=builder.complete(); builder.abort(); if !candidate.present { return 0,false,blot_error::Error.none; }
 let prepared,error=table.prepare(candidate.value); if error!=blot_error::Error.none { candidate.value.abort(); return 0,false,error; } if !prepared.present { candidate.value.abort(); return 0,false,blot_error::Error.none; } let position=table.publish(prepared.value,candidate.value).position; candidate.value.abort(); return position,true,blot_error::Error.none;
}

fn canonicalRecords(self_:Adapter,source:const Record[:])->Record[:] {if source.len==0 {return default<Record[:]>();}let owned=records.realloc_slice(source,source.len);assert(blot_support::same_slice_identity(owned,source));let start=records.index_of(owned[0]);assert(start>=0 && source.len<=records.len-start);return records[start..start+source.len];}
fn storeRecord(self_:Adapter,backing:Record[:],position:i64,value:Record) {let destination=self_.canonicalRecords(backing);assert(position>=0 && position<destination.len);destination[position]=self_.canonicalRecord(value);}
fn canonicalRecord(self_:Adapter,source:Record)->Record {return Record{source.key,blot_reuse_specialization_receipt::canonicalOwned(source.dependencies),source.value};}
