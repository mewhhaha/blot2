namespace blot_eval_selected_query;
import .core_eval;
import .eval_values;
import check.core;
import reuse.specialization_receipt;
import reuse.semantic_query_table;
import support.error;
import support.wyhash;
import support.option;
import support.host_layout;
type Error=blot_error::Error;
struct Source { unit: u32,identity: u32,origin: blot_eval_eval_values::ClosureOrigin,applied: u32,member: bool=false }
fn source(value: blot_eval_eval_values::ClosureValue) -> Source { return Source {value.unit,value.identity,value.origin,value.applied,false}; }
fn memberSource(target: blot_check_core::BindingRef) -> Source { return Source {target.unit,target.binding,blot_eval_eval_values::ClosureOrigin.named,0,true}; }
fn fingerprint(value: Source,options: blot_eval_core_eval::Options,depth: i64) -> u64 {
 var hash=blot_support_wyhash::init(0); hash.value(value.unit); hash.value(value.identity); hash.value(blot_eval_eval_values::closureOriginCode(value.origin)); hash.value(value.applied); hash.value(value.member); hash.value(options); hash.value(depth); return hash.final();
}
struct Key { source: Source,input: u32,expected: u32,options: blot_eval_core_eval::Options,depth: i64 }
fn deinit(self: Key&) {}
struct Result { selected: u32 }
fn deinit(self: Result&) {}
struct Adapter {}
type Record=blot_reuse_semantic_query_table::OwnedRecord<Key,blot_reuse_specialization_receipt::Record,Result,Adapter>;
type Table=blot_reuse_semantic_query_table::Table<Key,blot_reuse_specialization_receipt::Record,Result,Adapter>;
reusable[] var records: Record[>..]=[];
fn fingerprint(self: Adapter,key: Key) -> u64 { return fingerprint(key.source,key.options,key.depth); }
fn complete(self: Adapter,record: Record) -> bool {
 let proof=record.dependencies;
 if proof.member.present { if memberSource(proof.member.value.target)!=record.key.source { return false; } } else if record.key.source.member { return false; }
 return proof.complete&&proof.steps==0&&proof.input==record.key.input&&proof.expected==record.key.expected&&proof.selected==record.value.selected&&proof.depth==record.key.depth&&proof.options==record.key.options;
}
fn bytes(self: Adapter,record: Record) -> i64 { return blot_reuse_specialization_receipt::ownedBytes(record.dependencies); }
fn allocateRecords(self: Adapter,len: i64) -> Record[:],Error { return records.alloc_slice(len),Error.none; }
fn releaseRecords(self: Adapter,values: const Record[:]) { if values.len==0 { return; } let first: const Record&=values[0]; let at=records.index_of(first); assert(at>=0); records.free_slice(records[at..at+values.len]); }
fn recordBytes(self: Adapter) -> i64 { return blot_host_layout::selected_query_record; }
fn init() -> Table { return blot_reuse_semantic_query_table::init<Key,blot_reuse_specialization_receipt::Record,Result,Adapter>(Adapter {}); }
fn remember(table: Table&,closure: blot_eval_eval_values::ClosureValue,owned: blot_reuse_specialization_receipt::Record) -> u32,bool,Error {
 var origin=source(closure); if owned.member.present { origin=memberSource(owned.member.value.target); }
 var builder=table.begin(Key {origin,owned.input,owned.expected,owned.options,owned.depth}); builder.read(owned); builder.stage(Result {owned.selected});
 var candidate=builder.complete(); builder.abort(); if !candidate.present { return 0,false,Error.none; }
 let prepared,error=table.prepare(candidate.value); if error!=Error.none { candidate.value.abort(); return 0,false,error; } if !prepared.present { candidate.value.abort(); return 0,false,Error.none; } let position=table.publish(prepared.value,candidate.value).position; candidate.value.abort(); return position,true,Error.none;
}
