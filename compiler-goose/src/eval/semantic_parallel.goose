namespace blot_eval_semantic_parallel;
import .semantic_job_batch;
import reuse.independent_call_proof;
import reuse.specialization_receipt;
import support.error;
import support.option;
type Error=blot_error::Error;
type Record=blot_reuse_independent_call_proof::Record;
struct Request { index: i64,read: blot_reuse_specialization_receipt::CallRead,actual: u32 }
struct Counts { independent_regions: u64=0,independent_nodes: u64=0,independent_rejections: i64[15]=[0;15],independent_rechecked: i64=0,independent_reused: i64=0,independent_declined: i64=0 }
struct Slot { record: blot_support::Option<Record>=blot_support::none<Record>(),cached: i64=-1,failed: bool=false,counts: Counts=Counts {} }
struct Result { record: blot_support::Option<Record>=blot_support::none<Record>(),counts: Counts=Counts {} }
struct Batch { requests: const Request[:],slots: Slot[:],workers: i64=1,retained: Record[>..<]?=null }
fn deinit(self: Batch&) { for index in 0..self.slots.len { if self.slots[index].record.present { self.slots[index].record.value.deinit(); self.slots[index].record.present=false; } } self.slots=[]; self.requests=[]; }
fn attempted(self: const Batch&,index: i64) -> bool { for request in self.requests { if request.index==index { return true; } } return false; }
fn retainSuccesses(self: Batch&,owner: Record[>..<]&,words: i64&,limit: i64) {
 self.retained .= owner;
 for index in 0..self.slots.len { if !self.slots[index].record.present { continue; } let record=self.slots[index].record.value; let cost=16+record.sources.len*2+record.scalar_reads.len*6; var available=limit-words; if available<0 { available=0; } if cost>available { continue; }
  self.slots[index].cached=owner.len; owner.push(record); self.slots[index].record.present=false; words+=cost;
 }
}
fn take<S>(self: Batch&,index: i64,stats: S&) -> Record,bool,Error {
 for request,i in self.requests { if request.index!=index { continue; } let counts=self.slots[i].counts;
  stats.independent_rechecked+=counts.independent_rechecked; stats.independent_reused+=counts.independent_reused; stats.independent_declined+=counts.independent_declined; stats.independent_regions+=counts.independent_regions; stats.independent_nodes+=counts.independent_nodes;
  for count,j in counts.independent_rejections { stats.independent_rejections[j]+=count; } self.slots[i].counts=Counts {};
  if self.slots[i].failed { return default<Record>(),false,Error.out_of_memory; }
  if self.slots[i].cached>=0 { if self.retained==null { return default<Record>(),false,Error.invalid_artifact; } let record,error=self.retained[self.slots[i].cached].clone(); return record,error==Error.none,error; }
  let record=self.slots[i].record; self.slots[i].record.present=false; return record.value,record.present,Error.none;
 }
 return default<Record>(),false,Error.none;
}
// PacketContext encodes all source.old/gate/completed_worker_proofs/generator
// inputs. Execute reconstructs a private Session, calls independent.acquire,
// clones its complete result into the reply and carries all Counts back.
fn run<C,F>(requests: const Request[:],requested: u8,context: C&,owned_requests: Request[>..<]&,owned_slots: Slot[>..<]&,outcomes: blot_eval_semantic_job_batch::Outcome<Result>[>..<]&) -> Batch,Error {
 let request_start=owned_requests.len; owned_requests.append(requests); let slot_start=owned_slots.len; for request in requests { owned_slots.push(Slot {}); }
 var batch=Batch {owned_requests[request_start..],owned_slots[slot_start..],1,null}; var cancellation=blot_eval_semantic_job_batch::Cancellation {};
 let joined,error=blot_eval_semantic_job_batch::run<Result,Request,C,F>(batch.requests,requested,cancellation,context,outcomes,F); if error!=Error.none { return batch,error; } batch.workers=joined.workers;
 for outcome,index in joined.outcomes { match outcome {
  complete result=>{ batch.slots[index].record=result.value.record; batch.slots[index].counts=result.value.counts; },
  out_of_memory=>{ batch.slots[index].failed=true; },
  _=>{},
 } }
 return batch,Error.none;
}
