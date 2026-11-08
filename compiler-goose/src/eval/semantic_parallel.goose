namespace blot_eval_semantic_parallel;
import eval.semantic_job_batch;
import reuse.independent_worker;
import reuse.specialization_receipt;
import support.error;
import support.option;
import support.process_pool;

import reuse.independent_call_proof;
import support.pooled_buffer;
type Error=blot_error::Error;
type Record=blot_reuse_independent_call_proof::Record;
struct Request { index: i64,read: blot_reuse_specialization_receipt::CallRead,actual: u32 }
struct Counts { independent_regions: u64=0,independent_nodes: u64=0,independent_rejections: i64[15]=[0;15],independent_rechecked: i64=0,independent_reused: i64=0,independent_declined: i64=0 }
struct Slot { record: blot_support::Option<Record> =blot_support::none<Record>(),cached: i64=-1,failed: bool=false,counts: Counts=Counts {} }
struct Result { record: blot_support::Option<Record> =blot_support::none<Record>(),counts: Counts=Counts {} }
struct Batch { requests: const Request[:],slots: Slot[:],workers: i64=1,retained: Records?=null }
fn deinit(self_: Batch&) { for index in 0..self_.slots.len { if self_.slots[index].record.present { self_.slots[index].record.value.deinit(); self_.slots[index].record.present=false; } } self_.slots=default<Slot[:]>(); self_.requests=default<const Request[:]>(); }
fn attempted(self_: const Batch&,index: i64) -> bool { for request in self_.requests { if request.index==index { return true; } } return false; }
fn retainSuccesses(self_: Batch&,owner: Records&,words: i64&,limit: i64) {
 self_.retained .= owner;
 for index in 0..self_.slots.len { if !self_.slots[index].record.present { continue; } let record=self_.slots[index].record.value; let cost=16+record.sources.len*2+record.scalar_reads.len*6; var available=limit-words; if available<0 { available=0; } if cost>available { continue; }
  self_.slots[index].cached=owner.len; owner.push(record); self_.slots[index].record.present=false; words+=cost;
 }
}
fn take<S>(self_: Batch&,index: i64,stats: S&) -> Record,bool,Error {
 for request,i in self_.requests { if request.index!=index { continue; } let counts=self_.slots[i].counts;
  stats.independent_rechecked+=counts.independent_rechecked; stats.independent_reused+=counts.independent_reused; stats.independent_declined+=counts.independent_declined; stats.independent_regions+=counts.independent_regions; stats.independent_nodes+=counts.independent_nodes;
  for count,j in counts.independent_rejections { stats.independent_rejections[j]+=count; } self_.slots[i].counts=Counts {};
  if self_.slots[i].failed { return default<Record>(),false,blot_error::Error.out_of_memory; }
  if self_.slots[i].cached>=0 { let retained .=self_.retained; if retained==null { return default<Record>(),false,blot_error::Error.invalid_artifact; } let record,error=retained.items[self_.slots[i].cached].clone(); return record,error==blot_error::Error.none,error; }
  let record=self_.slots[i].record; self_.slots[i].record.present=false; return record.value,record.present,blot_error::Error.none;
 }
 return default<Record>(),false,blot_error::Error.none;
}
// PacketContext encodes all source.old/gate/completed_worker_proofs/generator
// inputs. Execute reconstructs a private Session, calls independent.acquire,
// clones its complete result into the reply and carries all Counts back.
fn run<C>(requests: const Request[:],requested: u8,context: C&,owned_requests: Requests&,owned_slots: Slots&,outcomes: Outcomes&) -> Batch,Error {
 let request_start=owned_requests.len;let request_error=owned_requests.ensure(request_start+requests.len);if request_error!=blot_error::Error.none {return default<Batch>(),request_error;}
 let slot_start=owned_slots.len;let slot_error=owned_slots.ensure(slot_start+requests.len);if slot_error!=blot_error::Error.none {return default<Batch>(),slot_error;}
 owned_requests.append(requests);for request in requests {owned_slots.push(Slot {});}
 var batch=Batch {owned_requests.items[request_start..],owned_slots.items[slot_start..],1,null}; var cancellation=blot_eval_semantic_job_batch::Cancellation {};
 let joined,error=blot_eval_semantic_job_batch::runInto<Result,Request,C,Outcomes>(blot_process_pool::Kind.independent,batch.requests,requested,cancellation,context,outcomes); if error!=blot_error::Error.none { return batch,error; } batch.workers=joined.workers;
 for outcome,index in joined.outcomes { match outcome {
  complete result=>{ batch.slots[index].record=blot_reuse_independent_call_proof::canonicalOwned(result.value.record); batch.slots[index].counts=result.value.counts; },
  out_of_memory=>{ batch.slots[index].failed=true; },
  _=>{},
 } }
 return batch,blot_error::Error.none;
}

struct Requests { storage: Request[:]=default<Request[:]>(),items: Request[:]=default<Request[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Requests: Request[>..]=[];
fn ensure(self_: Requests&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Requests); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Requests&,value: Request) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Requests); self_.len=self_.items.len; }
fn append(self_: Requests&,values: const Request[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Requests); self_.len=self_.items.len; }
fn resize(self_: Requests&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Requests&,length: i64,value: Request) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Requests&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Requests&) { blot_support_pooled_buffer::deinit(self_,pool_Requests); self_.len=0; self_.failure=blot_error::Error.none; }
struct Records { storage: Record[:]=default<Record[:]>(),items: Record[:]=default<Record[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Records: Record[>..]=[];
fn ensure(self_: Records&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Records); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Records&,value: Record) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,blot_reuse_independent_call_proof::canonicalOwned(value),pool_Records); self_.len=self_.items.len; }
fn append(self_: Records&,values: const Record[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Records); self_.len=self_.items.len; }
fn resize(self_: Records&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Records&,length: i64,value: Record) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Records&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Records&) { blot_support_pooled_buffer::deinit(self_,pool_Records); self_.len=0; self_.failure=blot_error::Error.none; }
struct Slots {storage:Slot[:]=default<Slot[:]>(),items:Slot[:]=default<Slot[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Slots:Slot[>..];
fn ensure(self_:Slots&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Slots);return self_.failure;}
fn push(self_:Slots&,value:Slot) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Slots);self_.len=self_.items.len;}
fn append(self_:Slots&,values:const Slot[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Slots);self_.len=self_.items.len;}
fn resize(self_:Slots&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Slots&,length:i64,value:Slot) {if length<=self_.len {resize(self_,length);return;}let error=ensure(self_,length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Slots&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Slots&) {blot_support_pooled_buffer::deinit(self_,pool_Slots);self_.len=0;self_.failure=blot_error::Error.none;}
struct Outcomes {storage:blot_eval_semantic_job_batch::Outcome<Result>[:]=default<blot_eval_semantic_job_batch::Outcome<Result>[:]>(),items:blot_eval_semantic_job_batch::Outcome<Result>[:]=default<blot_eval_semantic_job_batch::Outcome<Result>[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Outcomes:blot_eval_semantic_job_batch::Outcome<Result>[>..];
fn ensure(self_:Outcomes&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}self_.failure=blot_support_pooled_buffer::ensure(self_,minimum,pool_Outcomes);return self_.failure;}
fn push(self_:Outcomes&,value:blot_eval_semantic_job_batch::Outcome<Result>) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Outcomes);self_.len=self_.items.len;}
fn append(self_:Outcomes&,values:const blot_eval_semantic_job_batch::Outcome<Result>[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Outcomes);self_.len=self_.items.len;}
fn resize(self_:Outcomes&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Outcomes&,length:i64,value:blot_eval_semantic_job_batch::Outcome<Result>) {if length<=self_.len {resize(self_,length);return;}let error=ensure(self_,length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:Outcomes&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Outcomes&) {blot_support_pooled_buffer::deinit(self_,pool_Outcomes);self_.len=0;self_.failure=blot_error::Error.none;}

fn recordsView(values:const Records&)->const Record[:] {return values.items;}
fn recordsView(values:const Record[:])->const Record[:] {return values;}
