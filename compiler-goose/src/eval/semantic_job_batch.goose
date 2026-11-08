// Bounded copied-process jobs. Every dispatched wave is joined before decode;
// publication stays with the coordinator and no semantic owner crosses the wire.
namespace blot_eval_semantic_job_batch;
import phase_profile;
import support.bytes;
import support.error;
import support.native;
import support.process_pool;

type Error=blot_error::Error;
struct Cancellation { stopped:u64=0 }
fn cancel(self_:Cancellation&) { blot_native::atomic_store(self_.stopped,1); }
fn cancelled(self_:const Cancellation&)->bool { return blot_native::atomic_load(self_.stopped)!=0; }
enum Outcome<T> { pending,complete { value:T },declined,out_of_memory,cancelled }
struct Batch<T> { outcomes:Outcome<T>[:],workers:i64=1 }
reusable[] var request_bytes:u8[>..]=[];
// The two envelope flags retain the original private-job decline/cancel boundary.
// Process transport failures remain failures rather than becoming semantic facts.
fn writeResult(output:u8[>..<]&,payload:const u8[:],present:bool,stopped:bool,telemetry:blot_phase_profile::WorkerSnapshot)->Error {
 if payload.len>blot_process_pool::packet_limit-282 { return blot_error::Error.artifact_limit; }
 var presence:u8=0; if present { presence=1; } var stop:u8=0; if stopped { stop=1; }
 output.push(presence); output.push(stop); for pass in telemetry.passes { appendWord(output,pass.us); appendWord(output,pass.cpu_us); appendWord(output,pass.input); appendWord(output,pass.output); appendWord(output,pass.calls); } output.append(payload); return blot_error::Error.none;
}
fn deinit<T,D>(self_:Batch<T>&) {
 for slot in self_.outcomes { match slot { complete c=>{ D(c.value); },_=>{}, } }
 self_.outcomes=default<Outcome<T>[:]>();
}
struct NativeOutcomes<T> { items:Outcome<T>[>..<]& }
fn ensure<T>(self_:NativeOutcomes<T>&,minimum:i64)->Error { let start=self_.items.len; while self_.items.len<minimum { self_.items.push(Outcome<T>.pending {}); } self_.items.resize(start); return blot_error::Error.none; }
fn push<T>(self_:NativeOutcomes<T>&,value:Outcome<T>) { self_.items.push(value); }
// Encoded Grow storage ends in this helper. Wave descriptors retain only exact
// owned byte runs, never references to an encoder's local growing array.
fn encodeRequest<R,C>(context:C&,request:R)->blot_process_pool::Request,Error {
 let payload,error=context.encode(request); if error!=blot_error::Error.none { return blot_process_pool::Request {bytes:[]},error; }
 if payload.len>blot_process_pool::packet_limit-30 { return blot_process_pool::Request {bytes:[]},blot_error::Error.artifact_limit; }
 let telemetry=blot_phase_profile::captureWorker(); let owned=request_bytes.alloc_slice(payload.len+30);
 blot_bytes::put_u32(owned,0,0x534a5032); blot_bytes::put_u32(owned,4,2); owned[8]=0; if telemetry.enabled { owned[8]=1; } blot_bytes::put_u32(owned,9,telemetry.build); blot_bytes::put_u64(owned,13,telemetry.started_ns); blot_bytes::put_u64(owned,21,telemetry.id_base); owned[29]=0; if telemetry.space==blot_phase_profile::Space.core { owned[29]=1; } for byte,index in payload { owned[30+index]=byte; }
 return blot_process_pool::Request {bytes:owned},blot_error::Error.none;
}
fn releaseRequests(requests:const blot_process_pool::Request[:]) {
 for request in requests { if request.bytes.len!=0 { request_bytes.free_slice(request.bytes); } }
}
fn run<T,R,C>(kind:blot_process_pool::Kind,requests:const R[:],requested:u8,cancellation:Cancellation&,context:C&,outcomes:Outcome<T>[>..<]&)->Batch<T>,Error {
 var output=NativeOutcomes<T> {outcomes}; return runInto<T,R,C,NativeOutcomes<T>>(kind,requests,requested,cancellation,context,output);
}
fn runInto<T,R,C,O>(kind:blot_process_pool::Kind,requests:const R[:],requested:u8,cancellation:Cancellation&,context:C&,outcomes:O&)->Batch<T>,Error {
 let start=outcomes.items.len; let capacity=outcomes.ensure(start+requests.len); if capacity!=blot_error::Error.none { return Batch<T> {outcomes:default<Outcome<T>[:]>(),workers:1},capacity; }
 for request in requests { outcomes.push(Outcome<T>.pending {}); }
 var batch=Batch<T> {outcomes.items[start..],1}; var width=requested as i64;
 if width>requests.len { width=requests.len; } if width>16 { width=16; } if width<1 { width=1; } batch.workers=width;
 var cursor:i64=0;
 while cursor<requests.len&&!cancelled(cancellation) {
  var packets:blot_process_pool::Request[16]=[blot_process_pool::Request {bytes:[]};16];
  var ordinals:i64[16]=[-1;16]; var count:i64=0;
  while count<width&&cursor<requests.len&&!cancelled(cancellation) {
   let index=cursor; cursor++; let packet,error=encodeRequest<R,C>(context,requests[index]);
   if error!=blot_error::Error.none { if error==blot_error::Error.out_of_memory { batch.outcomes[index]=Outcome<T>.out_of_memory {}; } else { batch.outcomes[index]=Outcome<T>.declined {}; } continue; }
   packets[count]=packet; ordinals[count]=index; count++;
  }
  if count==0 { continue; }
  var replies,error=blot_process_pool::run(kind,packets[..count],width as u8); releaseRequests(packets[..count]);
  if error!=blot_error::Error.none { cancel(cancellation); for ordinal in ordinals[..count] { if error==blot_error::Error.out_of_memory { batch.outcomes[ordinal]=Outcome<T>.out_of_memory {}; } else { batch.outcomes[ordinal]=Outcome<T>.cancelled {}; } } replies.deinit(); for &outcome in batch.outcomes { match outcome { pending=>{ outcome=Outcome<T>.cancelled {}; },_=>{}, } } return batch,error; }
  if replies.items.len!=count { replies.deinit(); cancel(cancellation); for &outcome in batch.outcomes { match outcome { pending=>{ outcome=Outcome<T>.cancelled {}; },_=>{}, } } return batch,blot_error::Error.invalid_artifact; }
  for reply,index in replies.items {
   let ordinal=ordinals[index];
   if reply.failure!=blot_error::Error.none { if reply.failure==blot_error::Error.out_of_memory { batch.outcomes[ordinal]=Outcome<T>.out_of_memory {}; } else { batch.outcomes[ordinal]=Outcome<T>.declined {}; } continue; }
   if reply.bytes.len<282||reply.bytes[0]>1||reply.bytes[1]>1 { replies.deinit(); cancel(cancellation); for &outcome in batch.outcomes { match outcome { pending=>{ outcome=Outcome<T>.cancelled {}; },_=>{}, } } return batch,blot_error::Error.invalid_artifact; }
   mergeTelemetry(reply.bytes); if reply.bytes[1]!=0 { cancel(cancellation); }
   if reply.bytes[0]==0 { batch.outcomes[ordinal]=Outcome<T>.declined {}; continue; }
   let value,error=context.decode(reply.bytes[282..]); if error!=blot_error::Error.none { if error==blot_error::Error.out_of_memory { batch.outcomes[ordinal]=Outcome<T>.out_of_memory {}; } else { batch.outcomes[ordinal]=Outcome<T>.declined {}; } } else { batch.outcomes[ordinal]=Outcome<T>.complete {value:value}; }
  }
  replies.deinit();
 }
 for &outcome in batch.outcomes { match outcome { pending=>{ outcome=Outcome<T>.cancelled {}; },_=>{}, } }
 return batch,blot_error::Error.none;
}

fn appendWord(output:u8[>..<]&,word:u64) {for shift in 8 {output.push((word>>(shift*8)) as! u8);}}
fn unpackRequest(bytes:const u8[:])->const u8[:],blot_phase_profile::WorkerContext,Error {
 var context=blot_phase_profile::WorkerContext{..}; if bytes.len<30||blot_bytes::get_u32(bytes,0)!=0x534a5032||blot_bytes::get_u32(bytes,4)!=2||bytes[8]>1||bytes[29]>1 {return default<const u8[:]>(),context,blot_error::Error.invalid_artifact;}
 context.enabled=bytes[8]!=0;context.build=blot_bytes::get_u32(bytes,9);context.started_ns=blot_bytes::get_u64(bytes,13);context.id_base=blot_bytes::get_u64(bytes,21);if bytes[29]!=0 {context.space=blot_phase_profile::Space.core;}return bytes[30..],context,blot_error::Error.none;
}
fn mergeTelemetry(bytes:const u8[:]) {assert(bytes.len>=282);var snapshot=blot_phase_profile::WorkerSnapshot{..};var at:i64=2;for &pass in snapshot.passes {pass.us=blot_bytes::get_u64(bytes,at);pass.cpu_us=blot_bytes::get_u64(bytes,at+8);pass.input=blot_bytes::get_u64(bytes,at+16);pass.output=blot_bytes::get_u64(bytes,at+24);pass.calls=blot_bytes::get_u64(bytes,at+32);at+=40;}blot_phase_profile::mergeWorker(snapshot);}
