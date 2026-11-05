// Semantic row labels and operation arguments never cross owners unmapped.
namespace blot_check_effect_evidence;
import std;
import check.types;
import support.pooled_buffer;
import support.pooled_map;
import support.wyhash;
import dictionary;
import support.error;
import support.option;
import support.native;
type Id = u32;
type Label = u32;
type Error = blot_error::Error;
struct List { start: u32 = 0, len: u32 = 0 }
struct Row { start: u32 = 0, len: u32 = 0, formal: u32 = 0 }
struct Operation { identity: blot_check_types::NominalIdentity, arguments: List, instance: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { 0, 0 } }
struct View { operations: const Operation[:] = [], arguments: const u32[:] = [], rows: const Row[:] = [], labels: const Label[:] = [], owner_id: u64 = 0 }
fn operation(self: View, label: Label) -> Operation { return self.operations[label]; }
fn operationArguments(self: View, label: Label) -> const u32[:] { let span = operation(self, label).arguments; return self.arguments[span.start..span.start + span.len]; }
fn rowLabels(self: View, row: Id) -> const Label[:] { if row == 0 { return self.labels[..0]; } let span = self.rows[row]; return self.labels[span.start..span.start + span.len]; }
struct Snapshot { operations: const Operation[:], arguments: const u32[:], rows: const Row[:], labels: const Label[:], owner_id: u64 }
struct SnapshotTables { operations: Operation[>..]&, arguments: u32[>..]&, rows: Row[>..]&, labels: Label[>..]& }
fn view(self: const Snapshot&) -> View { return View { self.operations, self.arguments, self.rows, self.labels, self.owner_id }; }
fn deinit(self: Snapshot&) { self.operations = []; self.arguments = []; self.rows = []; self.labels = []; self.owner_id = 0; }
struct OperationBuffer { storage: Operation[:]=[],items: Operation[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_OperationBuffer: Operation[>..]=[];
fn ensure(self: OperationBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_OperationBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: OperationBuffer&,value: Operation) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_OperationBuffer); self.len=self.items.len; }
fn append(self: OperationBuffer&,values: const Operation[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_OperationBuffer); self.len=self.items.len; }
fn resize(self: OperationBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: OperationBuffer&,length: i64,value: Operation) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: OperationBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: OperationBuffer&) { blot_support_pooled_buffer::deinit(self,pool_OperationBuffer); self.len=0; self.failure=Error.none; }
struct RowBuffer { storage: Row[:]=[],items: Row[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RowBuffer: Row[>..]=[];
fn ensure(self: RowBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RowBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RowBuffer&,value: Row) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RowBuffer); self.len=self.items.len; }
fn append(self: RowBuffer&,values: const Row[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RowBuffer); self.len=self.items.len; }
fn resize(self: RowBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: RowBuffer&,length: i64,value: Row) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: RowBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RowBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RowBuffer); self.len=0; self.failure=Error.none; }
struct WordBuffer { storage: u32[:]=[],items: u32[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_WordBuffer: u32[>..]=[];
fn ensure(self: WordBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_WordBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: WordBuffer&,value: u32) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_WordBuffer); self.len=self.items.len; }
fn append(self: WordBuffer&,values: const u32[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_WordBuffer); self.len=self.items.len; }
fn resize(self: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: WordBuffer&,length: i64,value: u32) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: WordBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self,pool_WordBuffer); self.len=0; self.failure=Error.none; }
type Buckets=blot_support_pooled_map::Map<u64,u32>;
reusable[] var bucket_slots: dictionary_slot<u64,u32>[>..]=[];
fn get(self: const Buckets&,key: u64) -> u32? { return blot_support_pooled_map::get(self,key); }
fn insert(self: Buckets&,key: u64,value: u32) { blot_support_pooled_map::insert(self,key,value,bucket_slots); }
fn clear(self: Buckets&) { blot_support_pooled_map::clear(self); }
fn deinit(self: Buckets&) { blot_support_pooled_map::deinit(self,bucket_slots); }
fn reserve(self: Buckets&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return Error.out_of_memory; } var capacity=max(8,self.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self.slots.len { blot_support_pooled_map::grow(self,capacity,bucket_slots); } return Error.none; }
fn copyBuckets(destination: Buckets&,source: const Buckets&) { if destination.slots.len!=0 { bucket_slots.free_slice(destination.slots); } destination.slots=[]; destination.count=source.count; if source.slots.len!=0 { destination.slots=bucket_slots.alloc_slice(source.slots.len); for slot,index in source.slots { destination.slots[index]=slot; } } }
reusable[] var scratch_words: u32[>..]=[];
struct State { owner_id: u64=0,generation: u64=0,operations: OperationBuffer=OperationBuffer {},arguments: WordBuffer=WordBuffer {},rows: RowBuffer=RowBuffer {},labels: WordBuffer=WordBuffer {},operation_next: WordBuffer=WordBuffer {},row_next: WordBuffer=WordBuffer {},operation_buckets: Buckets=Buckets {},row_buckets: Buckets=Buckets {} }
reusable var states: State[>..]=[];
var next_generation: u64=1;
var inactive_OperationBuffer: OperationBuffer=OperationBuffer {};
var inactive_WordBuffer: WordBuffer=WordBuffer {};
var inactive_RowBuffer: RowBuffer=RowBuffer {};
var inactive_Buckets: Buckets=Buckets {};
struct Store { owner_id: u64=0,lease: u32=0,generation: u64=0,operations: OperationBuffer&=inactive_OperationBuffer,arguments: WordBuffer&=inactive_WordBuffer,rows: RowBuffer&=inactive_RowBuffer,labels: WordBuffer&=inactive_WordBuffer,operation_next: WordBuffer&=inactive_WordBuffer,row_next: WordBuffer&=inactive_WordBuffer,operation_buckets: Buckets&=inactive_Buckets,row_buckets: Buckets&=inactive_Buckets }
fn valid(self: const Store&) -> bool { return self.lease!=0&&self.lease-1<states.len&&states[self.lease-1].owner_id==self.owner_id&&states[self.lease-1].generation==self.generation&&self.owner_id!=0; }
fn init() -> Store,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Store {},Error.out_of_memory; } let generation=next_generation; next_generation++; let owner=blot_native::fresh_owner_id(); let index=states.alloc_index(State {owner_id:owner,generation:generation}); let state: State&=states[index]; var self=Store {owner_id:owner,lease:(index+1) as u32,generation:generation,operations:state.operations,arguments:state.arguments,rows:state.rows,labels:state.labels,operation_next:state.operation_next,row_next:state.row_next,operation_buckets:state.operation_buckets,row_buckets:state.row_buckets}; self.operations.push(Operation {blot_check_types::NominalIdentity {0,0},List {}}); self.operation_next.push(0); self.rows.push(Row {}); self.row_next.push(0); return self,Error.none; }
fn deinit(self: Store&) { if self.lease==0 { return; } assert(valid(self)); self.operations.deinit(); self.arguments.deinit(); self.rows.deinit(); self.labels.deinit(); self.operation_next.deinit(); self.row_next.deinit(); self.operation_buckets.deinit(); self.row_buckets.deinit(); let index=self.lease-1; states[index].owner_id=0; states.free(index); self=Store {}; }
fn view(self: const Store&) -> View { assert(valid(self)); return View {self.operations.items,self.arguments.items,self.rows.items,self.labels.items,self.owner_id}; }
fn copyOwned(self: const Store&,target: SnapshotTables) -> Snapshot,Error { let os=target.operations.len; let ars=target.arguments.len; let rs=target.rows.len; let ls=target.labels.len; target.operations.append(self.operations.items); target.arguments.append(self.arguments.items); target.rows.append(self.rows.items); target.labels.append(self.labels.items); return Snapshot {target.operations[os..],target.arguments[ars..],target.rows[rs..],target.labels[ls..],blot_native::fresh_owner_id()},Error.none; }
fn clone(self: const Store&) -> Store,Error { let initialized,error=init(); if error!=Error.none { return Store {},error; } var result=initialized; result.operations.clear(); result.operations.append(self.operations.items); result.arguments.clear(); result.arguments.append(self.arguments.items); result.rows.clear(); result.rows.append(self.rows.items); result.labels.clear(); result.labels.append(self.labels.items); result.operation_next.clear(); result.operation_next.append(self.operation_next.items); result.row_next.clear(); result.row_next.append(self.row_next.items); copyBuckets(result.operation_buckets,self.operation_buckets); copyBuckets(result.row_buckets,self.row_buckets); return result,Error.none; }
fn internOperation(self: Store, identity: blot_check_types::NominalIdentity, values: const u32[:]) -> Label, Error {
    return internOperationInstance(self, identity, values, blot_check_types::NominalIdentity { 0, 0 });
}
fn hashWord(hash: blot_support_wyhash::Wyhash&,value: u32) { let bytes: u8[4]=[value as! u8,(value>>8) as! u8,(value>>16) as! u8,(value>>24) as! u8]; hash.update(bytes); }
fn operationFingerprint(identity: blot_check_types::NominalIdentity,values: const u32[:],instance: blot_check_types::NominalIdentity) -> u64 { var hash=blot_support_wyhash::init(0); if instance.decl!=0 { hashWord(hash,instance.unit); hashWord(hash,instance.decl); } hashWord(hash,identity.unit); hashWord(hash,identity.decl); for value in values { hashWord(hash,value); } return hash.final(); }
fn rowFingerprint(values: const Label[:],formal: u32) -> u64 { var hash=blot_support_wyhash::init(formal as u64); for value in values { hashWord(hash,value); } return hash.final(); }
fn internOperationInstance(self: Store, identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity) -> Label, Error {
    return internOperationInstanceHashed(self, identity, values, instance, operationFingerprint(identity, values, instance));
}
fn internOperationHashed(self: Store, identity: blot_check_types::NominalIdentity, values: const u32[:], fingerprint: u64) -> Label, Error {
    return internOperationInstanceHashed(self, identity, values, blot_check_types::NominalIdentity { 0, 0 }, fingerprint);
}
fn internOperationInstanceHashed(self: Store, identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity, fingerprint: u64) -> Label, Error {
    if identity.decl == 0 || (identity.unit == 0 && identity.decl == 1 && (instance.unit != 0 || instance.decl != 0)) { return 0, Error.type_mismatch; }
    for value in values { if value == 0 { return 0, Error.type_mismatch; } }
    var candidate: u32 = 0;
    block { let bucket = self.operation_buckets.get(fingerprint); if bucket { candidate = bucket; } }
    while candidate != 0 {
        let op = operation(view(self), candidate);
        if op.instance.unit == instance.unit && op.instance.decl == instance.decl && op.identity.unit == identity.unit && op.identity.decl == identity.decl && operationArguments(view(self), candidate) == values { return candidate, Error.none; }
        candidate = self.operation_next.items[candidate];
    }
    if self.operations.len >= 0xffffffff || values.len > 0xffffffff || self.arguments.len > 0xffffffff - values.len { return 0, Error.evidence_limit; }
    let owned=scratch_words.alloc_slice(values.len); for value,index in values { owned[index]=value; }
    var previous: u32 = 0;
    block { let bucket = self.operation_buckets.get(fingerprint); if bucket { previous = bucket; } }
    let label = self.operations.len as u32;
    self.operations.push(Operation { identity, List { self.arguments.len as u32, owned.len as u32 }, instance });
    self.arguments.append(owned); self.operation_next.push(previous); self.operation_buckets.insert(fingerprint, label);
    scratch_words.free_slice(owned); return label, Error.none;
}
fn internRow(self: Store, values: const Label[:]) -> Id, Error { return internRowWithFormal(self, values, 0); }
fn internRowWithFormal(self: Store, values: const Label[:], formal: u32) -> Id, Error {
    if values.len == 0 && formal == 0 { return 0, Error.none; }
    var ordered = true; var previous: Label = 0;
    for label in values {
        if label == 0 || label >= self.operations.len { return 0, Error.type_mismatch; }
        ordered = ordered && previous <= label; previous = label;
    }
    if ordered { let known = findRow(self, values, formal, rowFingerprint(values, formal)); if known.present { return known.value, Error.none; } }
    let owned=scratch_words.alloc_slice(values.len); for value,index in values { owned[index]=value; } if !ordered { ::sort(owned); }
    let result,error=internRowFormalHashed(self, owned, formal, rowFingerprint(owned, formal)); scratch_words.free_slice(owned); return result,error;
}
fn internRowHashed(self: Store, values: const Label[:], fingerprint: u64) -> Id, Error { return internRowFormalHashed(self, values, 0, fingerprint); }
fn findRow(self: const Store&, values: const Label[:], formal: u32, fingerprint: u64) -> blot_support::Option<Id> {
    var candidate: Id = 0;
    block { let bucket = self.row_buckets.get(fingerprint); if bucket { candidate = bucket; } }
    while candidate != 0 {
        if self.rows.items[candidate].formal == formal && rowLabels(view(self), candidate) == values { return blot_support::Option<Id> { true, candidate }; }
        candidate = self.row_next.items[candidate];
    }
    return blot_support::Option<Id> { false, 0 };
}
fn internRowFormalHashed(self: Store, values: const Label[:], formal: u32, fingerprint: u64) -> Id, Error {
    let known = findRow(self, values, formal, fingerprint); if known.present { return known.value, Error.none; }
    if self.rows.len >= 0xffffffff || values.len > 0xffffffff || self.labels.len > 0xffffffff - values.len { return 0, Error.evidence_limit; }
    var previous: Id = 0;
    block { let bucket = self.row_buckets.get(fingerprint); if bucket { previous = bucket; } }
    let id = self.rows.len as u32;
    self.rows.push(Row { self.labels.len as u32, values.len as u32, formal }); self.labels.append(values);
    self.row_next.push(previous); self.row_buckets.insert(fingerprint, id);
    return id, Error.none;
}

fn prepareCommit(source: const Store&,destination: Store&) -> Error { if !valid(source)||!valid(destination)||source.owner_id==destination.owner_id { return Error.type_mismatch; }
 if source.operations.failure!=Error.none { return source.operations.failure; }
 if source.arguments.failure!=Error.none { return source.arguments.failure; }
 if source.rows.failure!=Error.none { return source.rows.failure; }
 if source.labels.failure!=Error.none { return source.labels.failure; }
 if source.operation_next.failure!=Error.none { return source.operation_next.failure; }
 if source.row_next.failure!=Error.none { return source.row_next.failure; }
 return Error.none; }
fn commit(source: Store&,destination: Store&) { assert(valid(source)&&valid(destination)&&source.owner_id!=destination.owner_id);
 destination.operations.deinit(); destination.operations=source.operations; source.operations=OperationBuffer {};
 destination.arguments.deinit(); destination.arguments=source.arguments; source.arguments=WordBuffer {};
 destination.rows.deinit(); destination.rows=source.rows; source.rows=RowBuffer {};
 destination.labels.deinit(); destination.labels=source.labels; source.labels=WordBuffer {};
 destination.operation_next.deinit(); destination.operation_next=source.operation_next; source.operation_next=WordBuffer {};
 destination.row_next.deinit(); destination.row_next=source.row_next; source.row_next=WordBuffer {};
 destination.operation_buckets.deinit(); destination.operation_buckets=source.operation_buckets; source.operation_buckets=Buckets {};
 destination.row_buckets.deinit(); destination.row_buckets=source.row_buckets; source.row_buckets=Buckets {};
 let identity=destination.owner_id; destination.owner_id=source.owner_id; states[destination.lease-1].owner_id=destination.owner_id; source.owner_id=identity; states[source.lease-1].owner_id=source.owner_id; }
