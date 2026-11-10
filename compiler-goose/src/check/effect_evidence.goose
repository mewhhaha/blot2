// Semantic row labels and operation arguments never cross owners unmapped.
namespace blot_check_effect_evidence;
import check.types;
import support.error;
import support.native;
import support.option;
import support.pooled_buffer;
import support.u64_id_map;
import support.wyhash;

import std;
type Id = u32;
type Label = u32;
type Error = blot_error::Error;
struct List { start: u32 = 0, len: u32 = 0 }
struct Row { start: u32 = 0, len: u32 = 0, formal: u32 = 0 }
struct Operation { identity: blot_check_types::NominalIdentity, arguments: List, instance: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { 0, 0 } }
struct View { operations: const Operation[:] = default<const Operation[:]>(), arguments: const u32[:] = default<const u32[:]>(), rows: const Row[:] = default<const Row[:]>(), labels: const Label[:] = default<const Label[:]>(), owner_id: u64 = 0 }
fn operation(self_: View, label: Label) -> Operation { return self_.operations[label]; }
fn operationArguments(self_: View, label: Label) -> const u32[:] { let span = operation(self_, label).arguments; return self_.arguments[span.start..span.start + span.len]; }
fn rowLabels(self_: View, row: Id) -> const Label[:] { if row == 0 { return self_.labels[..0]; } let span = self_.rows[row]; return self_.labels[span.start..span.start + span.len]; }
struct Snapshot { operations: const Operation[:], arguments: const u32[:], rows: const Row[:], labels: const Label[:], owner_id: u64 }
struct SnapshotTables { operations: Operation[>..]&, arguments: u32[>..]&, rows: Row[>..]&, labels: Label[>..]& }
fn view(self_: Snapshot) -> View { return View { self_.operations, self_.arguments, self_.rows, self_.labels, self_.owner_id }; }
fn deinit(self_: Snapshot&) { self_.operations = default<const blot_check_effect_evidence::Operation[:]>(); self_.arguments = default<const u32[:]>(); self_.rows = default<const blot_check_effect_evidence::Row[:]>(); self_.labels = default<const blot_check_effect_evidence::Label[:]>(); self_.owner_id = 0; }
struct OperationBuffer { storage: Operation[:]=default<Operation[:]>(),items: Operation[:]=default<Operation[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_OperationBuffer: Operation[>..]=[];
fn ensure(self_: OperationBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_OperationBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: OperationBuffer&,value: Operation) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_OperationBuffer); self_.len=self_.items.len; }
fn append(self_: OperationBuffer&,values: const Operation[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_OperationBuffer); self_.len=self_.items.len; }
fn resize(self_: OperationBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: OperationBuffer&,length: i64,value: Operation) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: OperationBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: OperationBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_OperationBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RowBuffer { storage: Row[:]=default<Row[:]>(),items: Row[:]=default<Row[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RowBuffer: Row[>..]=[];
fn ensure(self_: RowBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RowBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RowBuffer&,value: Row) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RowBuffer); self_.len=self_.items.len; }
fn append(self_: RowBuffer&,values: const Row[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RowBuffer); self_.len=self_.items.len; }
fn resize(self_: RowBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: RowBuffer&,length: i64,value: Row) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: RowBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RowBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RowBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct WordBuffer { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_WordBuffer: u32[>..]=[];
fn ensure(self_: WordBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_WordBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: WordBuffer&,value: u32) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_WordBuffer); self_.len=self_.items.len; }
fn append(self_: WordBuffer&,values: const u32[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_WordBuffer); self_.len=self_.items.len; }
fn resize(self_: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: WordBuffer&,length: i64,value: u32) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: WordBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: WordBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_WordBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
type Buckets=blot_support_u64_id_map::Buckets;
reusable[] var scratch_words: u32[>..]=[];
struct State { owner_id: u64=0,generation: u64=0,operations: OperationBuffer=OperationBuffer {},arguments: WordBuffer=WordBuffer {},rows: RowBuffer=RowBuffer {},labels: WordBuffer=WordBuffer {},operation_next: WordBuffer=WordBuffer {},row_next: WordBuffer=WordBuffer {},operation_buckets: Buckets=Buckets {},row_buckets: Buckets=Buckets {} }
reusable var states: State[>..]=[];
var next_generation: u64=1;
var inactive_OperationBuffer: OperationBuffer=OperationBuffer {};
var inactive_WordBuffer: WordBuffer=WordBuffer {};
var inactive_RowBuffer: RowBuffer=RowBuffer {};
var inactive_Buckets: Buckets=Buckets {};
struct Store { owner_id: u64=0,lease: u32=0,generation: u64=0,operations: OperationBuffer& =inactive_OperationBuffer,arguments: WordBuffer& =inactive_WordBuffer,rows: RowBuffer& =inactive_RowBuffer,labels: WordBuffer& =inactive_WordBuffer,operation_next: WordBuffer& =inactive_WordBuffer,row_next: WordBuffer& =inactive_WordBuffer,operation_buckets: Buckets& =inactive_Buckets,row_buckets: Buckets& =inactive_Buckets }
fn valid(self_: const Store&) -> bool { return self_.lease!=0&&self_.lease-1<states.len&&states[self_.lease-1].owner_id==self_.owner_id&&states[self_.lease-1].generation==self_.generation&&self_.owner_id!=0; }
// A scalar key names only its original live owner lease.
struct Handle { owner_id:u64=0,lease:u32=0,generation:u64=0 }
fn valid(key:Handle)->bool {return key.lease!=0&&key.lease-1<states.len&&key.owner_id!=0&&states[key.lease-1].owner_id==key.owner_id&&states[key.lease-1].generation==key.generation;}
fn handle(source:const Store&)->Handle {
 assert(valid(source));let state:State& =states[source.lease-1];
 assert(source.operations .== state.operations);
 assert(source.arguments .== state.arguments);
 assert(source.rows .== state.rows);
 assert(source.labels .== state.labels);
 assert(source.operation_next .== state.operation_next);
 assert(source.row_next .== state.row_next);
 assert(source.operation_buckets .== state.operation_buckets);
 assert(source.row_buckets .== state.row_buckets);
 return Handle{source.owner_id,source.lease,source.generation};
}
fn fromHandle(key:Handle)->Store {
 assert(valid(key));let state:State& =states[key.lease-1];
 return Store{owner_id:key.owner_id,lease:key.lease,generation:key.generation,operations:state.operations,arguments:state.arguments,rows:state.rows,labels:state.labels,operation_next:state.operation_next,row_next:state.row_next,operation_buckets:state.operation_buckets,row_buckets:state.row_buckets};
}
fn deinit(key:Handle&) {if key.lease==0 {return;}var source=fromHandle(key);source.deinit();key=Handle{};}
fn init() -> Store,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Store {},blot_error::Error.out_of_memory; } let generation=next_generation; next_generation++; let owner=blot_native::fresh_owner_id(); let index=states.alloc_index(State {owner_id:owner,generation:generation}); let state: State& =states[index]; var self_=Store {owner_id:owner,lease:(index+1) as u32,generation:generation,operations:state.operations,arguments:state.arguments,rows:state.rows,labels:state.labels,operation_next:state.operation_next,row_next:state.row_next,operation_buckets:state.operation_buckets,row_buckets:state.row_buckets}; self_.operations.push(Operation {blot_check_types::NominalIdentity {0,0},List {}}); self_.operation_next.push(0); self_.rows.push(Row {}); self_.row_next.push(0); return self_,blot_error::Error.none; }
fn deinit(self_: Store&) { if self_.lease==0 { return; } assert(valid(self_)); self_.operations.deinit(); self_.arguments.deinit(); self_.rows.deinit(); self_.labels.deinit(); self_.operation_next.deinit(); self_.row_next.deinit(); self_.operation_buckets.deinit(); self_.row_buckets.deinit(); let index=self_.lease-1; states[index].owner_id=0; states.free(index); self_=Store {}; }
fn view(self_: const Store&) -> View { assert(valid(self_)); return View {self_.operations.items,self_.arguments.items,self_.rows.items,self_.labels.items,self_.owner_id}; }
fn copyOwned(self_: const Store&,target: SnapshotTables) -> Snapshot,Error { let os=target.operations.len; let ars=target.arguments.len; let rs=target.rows.len; let ls=target.labels.len; target.operations.append(self_.operations.items); target.arguments.append(self_.arguments.items); target.rows.append(self_.rows.items); target.labels.append(self_.labels.items); return Snapshot {target.operations[os..],target.arguments[ars..],target.rows[rs..],target.labels[ls..],blot_native::fresh_owner_id()},blot_error::Error.none; }
fn clone(self_: const Store&) -> Store,Error { let initialized,error=init(); if error!=blot_error::Error.none { return Store {},error; } var result=initialized; result.operations.clear(); result.operations.append(self_.operations.items); result.arguments.clear(); result.arguments.append(self_.arguments.items); result.rows.clear(); result.rows.append(self_.rows.items); result.labels.clear(); result.labels.append(self_.labels.items); result.operation_next.clear(); result.operation_next.append(self_.operation_next.items); result.row_next.clear(); result.row_next.append(self_.row_next.items); blot_support_u64_id_map::copyBuckets(result.operation_buckets,self_.operation_buckets); blot_support_u64_id_map::copyBuckets(result.row_buckets,self_.row_buckets); return result,blot_error::Error.none; }
fn internOperation(self_: Store, identity: blot_check_types::NominalIdentity, values: const u32[:]) -> Label, Error {
    return internOperationInstance(self_, identity, values, blot_check_types::NominalIdentity { 0, 0 });
}
fn hashWord(hash: blot_support_wyhash::Wyhash&,value: u32) { let bytes: u8[4]=[value as! u8,(value>>8) as! u8,(value>>16) as! u8,(value>>24) as! u8]; hash.update(bytes); }
fn operationFingerprint(identity: blot_check_types::NominalIdentity,values: const u32[:],instance: blot_check_types::NominalIdentity) -> u64 { var hash=blot_support_wyhash::init(0); if instance.decl!=0 { hashWord(hash,instance.unit); hashWord(hash,instance.decl); } hashWord(hash,identity.unit); hashWord(hash,identity.decl); for value in values { hashWord(hash,value); } return hash.final(); }
fn rowFingerprint(values: const Label[:],formal: u32) -> u64 { var hash=blot_support_wyhash::init(formal as u64); for value in values { hashWord(hash,value); } return hash.final(); }
fn internOperationInstance(self_: Store, identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity) -> Label, Error {
    return internOperationInstanceHashed(self_, identity, values, instance, operationFingerprint(identity, values, instance));
}
fn internOperationHashed(self_: Store, identity: blot_check_types::NominalIdentity, values: const u32[:], fingerprint: u64) -> Label, Error {
    return internOperationInstanceHashed(self_, identity, values, blot_check_types::NominalIdentity { 0, 0 }, fingerprint);
}
fn internOperationInstanceHashed(self_: Store, identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity, fingerprint: u64) -> Label, Error {
    if identity.decl == 0 || (identity.unit == 0 && identity.decl == 1 && (instance.unit != 0 || instance.decl != 0)) { return 0, blot_error::Error.type_mismatch; }
    for value in values { if value == 0 { return 0, blot_error::Error.type_mismatch; } }
    var candidate: u32 = 0;
    block { let bucket = self_.operation_buckets.get(fingerprint); if bucket { candidate = bucket; } }
    while candidate != 0 {
        let op = operation(view(self_), candidate);
        if op.instance.unit == instance.unit && op.instance.decl == instance.decl && op.identity.unit == identity.unit && op.identity.decl == identity.decl && operationArguments(view(self_), candidate) == values { return candidate, blot_error::Error.none; }
        candidate = self_.operation_next.items[candidate];
    }
    if self_.operations.len >= 0xffffffff || values.len > 0xffffffff || self_.arguments.len > 0xffffffff - values.len { return 0, blot_error::Error.evidence_limit; }
    let owned=scratch_words.alloc_slice(values.len); for value,index in values { owned[index]=value; }
    var previous: u32 = 0;
    block { let bucket = self_.operation_buckets.get(fingerprint); if bucket { previous = bucket; } }
    let label = self_.operations.len as u32;
    self_.operations.push(Operation { identity, List { self_.arguments.len as u32, owned.len as u32 }, instance });
    self_.arguments.append(owned); self_.operation_next.push(previous); self_.operation_buckets.insert(fingerprint, label);
    scratch_words.free_slice(owned); return label, blot_error::Error.none;
}
fn internRow(self_: Store, values: const Label[:]) -> Id, Error { return internRowWithFormal(self_, values, 0); }
fn internRowWithFormal(self_: Store, values: const Label[:], formal: u32) -> Id, Error {
    if values.len == 0 && formal == 0 { return 0, blot_error::Error.none; }
    var ordered = true; var previous: Label = 0;
    for label in values {
        if label == 0 || label >= self_.operations.len { return 0, blot_error::Error.type_mismatch; }
        ordered = ordered && previous <= label; previous = label;
    }
    if ordered { let known = findRow(self_, values, formal, rowFingerprint(values, formal)); if known.present { return known.value, blot_error::Error.none; } }
    let owned=scratch_words.alloc_slice(values.len); for value,index in values { owned[index]=value; } if !ordered { ::sort(owned); }
    let result,error=internRowFormalHashed(self_, owned, formal, rowFingerprint(owned, formal)); scratch_words.free_slice(owned); return result,error;
}
fn internRowHashed(self_: Store, values: const Label[:], fingerprint: u64) -> Id, Error { return internRowFormalHashed(self_, values, 0, fingerprint); }
fn findRow(self_: const Store&, values: const Label[:], formal: u32, fingerprint: u64) -> blot_support::Option<Id> {
    var candidate: Id = 0;
    block { let bucket = self_.row_buckets.get(fingerprint); if bucket { candidate = bucket; } }
    while candidate != 0 {
        if self_.rows.items[candidate].formal == formal && rowLabels(view(self_), candidate) == values { return blot_support::Option<Id> { true, candidate }; }
        candidate = self_.row_next.items[candidate];
    }
    return blot_support::Option<Id> { false, 0 };
}
fn internRowFormalHashed(self_: Store, values: const Label[:], formal: u32, fingerprint: u64) -> Id, Error {
    let known = findRow(self_, values, formal, fingerprint); if known.present { return known.value, blot_error::Error.none; }
    if self_.rows.len >= 0xffffffff || values.len > 0xffffffff || self_.labels.len > 0xffffffff - values.len { return 0, blot_error::Error.evidence_limit; }
    var previous: Id = 0;
    block { let bucket = self_.row_buckets.get(fingerprint); if bucket { previous = bucket; } }
    let id = self_.rows.len as u32;
    self_.rows.push(Row { self_.labels.len as u32, values.len as u32, formal }); self_.labels.append(values);
    self_.row_next.push(previous); self_.row_buckets.insert(fingerprint, id);
    return id, blot_error::Error.none;
}

fn prepareCommit(source: const Store&,destination: Store&) -> Error { if !valid(source)||!valid(destination)||source.owner_id==destination.owner_id { return blot_error::Error.type_mismatch; }
 if source.operations.failure!=blot_error::Error.none { return source.operations.failure; }
 if source.arguments.failure!=blot_error::Error.none { return source.arguments.failure; }
 if source.rows.failure!=blot_error::Error.none { return source.rows.failure; }
 if source.labels.failure!=blot_error::Error.none { return source.labels.failure; }
 if source.operation_next.failure!=blot_error::Error.none { return source.operation_next.failure; }
 if source.row_next.failure!=blot_error::Error.none { return source.row_next.failure; }
 return blot_error::Error.none; }
fn ownedBuffer(value:const OperationBuffer&)->OperationBuffer {
 assert(value.len>=0 && value.len==value.items.len && value.len<=value.storage.len);
 assert(blot_support::same_slice_identity(value.items,value.storage[..value.len]));
 if value.storage.len==0 {return OperationBuffer{failure:value.failure};}
 let registered=pool_OperationBuffer.realloc_slice(value.storage,value.storage.len);assert(blot_support::same_slice_identity(registered,value.storage));
 let start=pool_OperationBuffer.index_of(registered[0]);let storage=pool_OperationBuffer[start..start+registered.len];
 return OperationBuffer{storage:storage,items:storage[..value.len],len:value.len,failure:value.failure};
}
fn ownedBuffer(value:const RowBuffer&)->RowBuffer {
 assert(value.len>=0 && value.len==value.items.len && value.len<=value.storage.len);
 assert(blot_support::same_slice_identity(value.items,value.storage[..value.len]));
 if value.storage.len==0 {return RowBuffer{failure:value.failure};}
 let registered=pool_RowBuffer.realloc_slice(value.storage,value.storage.len);assert(blot_support::same_slice_identity(registered,value.storage));
 let start=pool_RowBuffer.index_of(registered[0]);let storage=pool_RowBuffer[start..start+registered.len];
 return RowBuffer{storage:storage,items:storage[..value.len],len:value.len,failure:value.failure};
}
fn ownedBuffer(value:const WordBuffer&)->WordBuffer {
 assert(value.len>=0 && value.len==value.items.len && value.len<=value.storage.len);
 assert(blot_support::same_slice_identity(value.items,value.storage[..value.len]));
 if value.storage.len==0 {return WordBuffer{failure:value.failure};}
 let registered=pool_WordBuffer.realloc_slice(value.storage,value.storage.len);assert(blot_support::same_slice_identity(registered,value.storage));
 let start=pool_WordBuffer.index_of(registered[0]);let storage=pool_WordBuffer[start..start+registered.len];
 return WordBuffer{storage:storage,items:storage[..value.len],len:value.len,failure:value.failure};
}
fn ownedBuckets(value:const Buckets&)->Buckets {return blot_support_u64_id_map::ownedBuckets(value);}
fn commit(source: Store&,destination: Store&) { assert(valid(source)&&valid(destination)&&source.owner_id!=destination.owner_id);
 destination.operations.deinit(); destination.operations=ownedBuffer(source.operations); source.operations=OperationBuffer {};
 destination.arguments.deinit(); destination.arguments=ownedBuffer(source.arguments); source.arguments=WordBuffer {};
 destination.rows.deinit(); destination.rows=ownedBuffer(source.rows); source.rows=RowBuffer {};
 destination.labels.deinit(); destination.labels=ownedBuffer(source.labels); source.labels=WordBuffer {};
 destination.operation_next.deinit(); destination.operation_next=ownedBuffer(source.operation_next); source.operation_next=WordBuffer {};
 destination.row_next.deinit(); destination.row_next=ownedBuffer(source.row_next); source.row_next=WordBuffer {};
 destination.operation_buckets.deinit(); destination.operation_buckets=ownedBuckets(source.operation_buckets); source.operation_buckets=Buckets {};
 destination.row_buckets.deinit(); destination.row_buckets=ownedBuckets(source.row_buckets); source.row_buckets=Buckets {};
 let identity=destination.owner_id; destination.owner_id=source.owner_id; states[destination.lease-1].owner_id=destination.owner_id; source.owner_id=identity; states[source.lease-1].owner_id=source.owner_id; }

// Handle operations borrow the existing descriptor only for this invocation.
fn view(key:Handle)->View {
 let source=fromHandle(key);let operations=ownedBuffer(source.operations);let arguments=ownedBuffer(source.arguments);let rows=ownedBuffer(source.rows);let labels=ownedBuffer(source.labels);
 return View{operations.items,arguments.items,rows.items,labels.items,key.owner_id};
}
fn internOperation(key:Handle,identity:blot_check_types::NominalIdentity,values:const u32[:])->Label,Error {return internOperation(fromHandle(key),identity,values);}
fn internOperationInstance(key:Handle,identity:blot_check_types::NominalIdentity,values:const u32[:],instance:blot_check_types::NominalIdentity)->Label,Error {return internOperationInstance(fromHandle(key),identity,values,instance);}
fn internRow(key:Handle,values:const Label[:])->Id,Error {return internRow(fromHandle(key),values);}
fn internRowWithFormal(key:Handle,values:const Label[:],formal:u32)->Id,Error {return internRowWithFormal(fromHandle(key),values,formal);}
