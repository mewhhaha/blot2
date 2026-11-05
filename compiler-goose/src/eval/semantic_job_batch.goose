// Joined private jobs. Full immutable context/request images cross copied queues;
// the coordinator owns decoding/publication after every contained worker joins.
namespace blot_eval_semantic_job_batch;
import support.error;
import support.native;
type Error=blot_error::Error;
struct Cancellation { stopped: u64=0 }
fn cancel(self: Cancellation&) { blot_native::atomic_store(self.stopped,1); }
fn cancelled(self: const Cancellation&) -> bool { return blot_native::atomic_load(self.stopped)!=0; }
enum Outcome<T> { pending,complete { value: T },declined,out_of_memory,cancelled }
struct Batch<T> { outcomes: Outcome<T>[:],workers: i64=1 }
struct Packet { batch: u64,index: i64,payload: u8[] }
struct Reply { batch: u64,index: i64,present: bool,cancelled: bool,error: Error,payload: u8[] }
let retained_scratch: i64=4194304;
// Execute is a compile-time function, never an erased runtime callback. It
// decodes all source/owner inputs into private typed tables and encodes a result.
thread_fn packetWorker<F>(packet: Packet) {
 let bytes,present,stop,error=F(packet.payload,retained_scratch);
 qput(Reply {packet.batch,packet.index,present,stop,error,copy(bytes)});
}
fn deinit<T,D>(self: Batch<T>&) {
 for slot in self.outcomes { match slot { complete c=>{ D(c.value); },_=>{}, } }
 self.outcomes=[];
}
// C.encode(request) includes every immutable context fact read by Execute.
// C.decode(reply) imports owned results; neither worker nor result borrows C.
fn run<T,R,C,F>(requests: const R[:],requested: u8,cancellation: Cancellation&,context: C&,outcomes: Outcome<T>[>..<]&) -> Batch<T>,Error {
 let start=outcomes.len; for request in requests { outcomes.push(Outcome<T>.pending); }
 var batch=Batch<T> {outcomes[start..],1}; var width=requested as i64; if width>requests.len { width=requests.len; } if width>16 { width=16; } if width<1 { width=1; }
 batch.workers=width; let identity=blot_native::fresh_owner_id(); var cursor=0;
 while cursor<requests.len&&!cancelled(cancellation) {
  var ids: i64[16]=[-1;16]; var ordinals: i64[16]=[-1;16]; var count=0;
  while count<width&&cursor<requests.len&&!cancelled(cancellation) {
   let index=cursor; cursor++; let payload,error=context.encode(requests[index]);
   if error!=Error.none { if error==Error.out_of_memory { batch.outcomes[index]=Outcome<T>.out_of_memory; } else { batch.outcomes[index]=Outcome<T>.declined; } continue; }
   ids[count]=thread_spawn_contained(packetWorker<F>,Packet {identity,index,copy(payload)}); ordinals[count]=index; count++;
  }
  var replies=0;
  for index in 0..count { if thread_wait(ids[index]) { replies++; } else { batch.outcomes[ordinals[index]]=Outcome<T>.out_of_memory; } }
  while replies>0 {
   let response=qget<Reply>(); if response.batch!=identity { qput(response); continue; } replies--;
   if response.index<0||response.index>=batch.outcomes.len { cancel(cancellation); continue; }
   if response.cancelled { cancel(cancellation); }
   if response.error!=Error.none { if response.error==Error.out_of_memory { batch.outcomes[response.index]=Outcome<T>.out_of_memory; } else { batch.outcomes[response.index]=Outcome<T>.declined; } }
   else if !response.present { batch.outcomes[response.index]=Outcome<T>.declined; }
   else { let value,error=context.decode(response.payload); if error!=Error.none { if error==Error.out_of_memory { batch.outcomes[response.index]=Outcome<T>.out_of_memory; } else { batch.outcomes[response.index]=Outcome<T>.declined; } } else { batch.outcomes[response.index]=Outcome<T>.complete {value:value}; } }
  }
 }
 for index in 0..batch.outcomes.len { match batch.outcomes[index] { pending=>{ batch.outcomes[index]=Outcome<T>.cancelled; },_=>{}, } }
 return batch,Error.none;
}
