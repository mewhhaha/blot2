// Copied packets cross ordinary process boundaries. No compiler stage is a C
// callback or a Goose thread_fn reaching non-flat mutable metadata globals.
namespace blot_process_pool;
import std;
import support.error;
import support.native;
import support.io;
import support.blake3;
type Error=blot_error::Error;
enum Kind {runtime,semantic,check,lower,independent}
let kinds=[Kind.runtime,Kind.semantic,Kind.check,Kind.lower,Kind.independent];
let magic:const u8[:]="BLOTJOB2";
let version:u32=2;
let header_size:i64=80;
let packet_limit:i64=536870912;
let worker_limit:i64=16;
struct Request {bytes:const u8[:]}
struct Reply {bytes:u8[:]=[],failure:Error=Error.none}
struct Replies {items:Reply[:]=[]}
struct Frame {kind:Kind=Kind.runtime,id:u64=0,inference_budget:u64=1000000,bytes:u8[:]=[],failure:Error=Error.none}
reusable[] var reply_headers:Reply[>..]=[];
reusable[] var payload_runs:u8[>..]=[];
var alive:bool[16]=[false;16];
var busy:bool=false;
var worker_child:bool=false;
var next_request:u64=1;
var inference_budget:u64=1000000;
fn configureBudget(limit:u64) {assert(limit!=0 && !busy);inference_budget=limit;}
fn markWorker() {assert(!busy);worker_child=true;}
fn release(bytes:u8[:]) {if bytes.len!=0 {payload_runs.free_slice(bytes);}}
fn deinit(self:Frame&) {release(self.bytes);self=Frame{..};}
fn deinit(self:Replies&) {for item in self.items {release(item.bytes);}if self.items.len!=0 {reply_headers.free_slice(self.items);}self=Replies{..};}
fn kindCode(kind:Kind)->u32 {for value,index in kinds {if value==kind {return index as u32;}}abort("invalid worker kind");}
fn fromKind(code:u32)->Kind,bool {if code>=kinds.len {return Kind.runtime,false;}return kinds[code],true;}
fn errorCode(error:Error)->u32 {var index:u32=0;const for <N,V> in variants<Error> {if error==V {return index;}index++;}abort("invalid error");}
fn fromError(code:u32)->Error,bool {var index:u32=0;const for <N,V> in variants<Error> {if code==index {return V,true;}index++;}return Error.invalid_artifact,false;}
fn put(bytes:u8[:],at:i64,value:u64,width:i64) {for index in width {bytes[at+index]=(value>>(index*8)) as! u8;}}
fn get(bytes:const u8[:],at:i64,width:i64)->u64 {var result:u64=0;for index in width {result|=bytes[at+index] as u64<<(index*8);}return result;}
fn writeFrame(writer:blot_io::Writer,kind:Kind,id:u64,bytes:const u8[:],failure:Error)->Error {
    if bytes.len>packet_limit {return Error.artifact_limit;}var header:u8[80]=[0;80];for byte,index in magic {header[index]=byte;}put(header,8,version,4);put(header,12,kindCode(kind),4);put(header,16,id,8);put(header,24,bytes.len as u64,8);put(header,32,errorCode(failure),4);put(header,36,0,4);put(header,40,inference_budget,8);let digest=blot_support_blake3::hash(bytes);for byte,index in digest {header[48+index]=byte;}let error=blot_io::write_all(writer,header);if error!=Error.none {return error;}return blot_io::write_all(writer,bytes);
}
fn readFrame(reader:blot_io::Reader)->Frame,Error {
    var header:u8[80]=[0;80];let used,error=blot_io::read_short(reader,header);if error!=Error.none {return Frame{..},error;}if used==0 {return Frame{..},Error.end_of_stream;}if used!=header_size || header[..8]!=magic || get(header,8,4)!=version || get(header,36,4)!=0 {return Frame{..},Error.invalid_artifact;}
    let kind,valid=fromKind(get(header,12,4) as u32);if !valid {return Frame{..},Error.invalid_artifact;}let failure,valid=fromError(get(header,32,4) as u32);if !valid {return Frame{..},Error.invalid_artifact;}let length=get(header,24,8);if length>packet_limit as u64 {return Frame{..},Error.artifact_limit;}let payload=payload_runs.alloc_slice(length as i64);let error=blot_io::read_all(reader,payload);if error!=Error.none {release(payload);return Frame{..},error;}if blot_support_blake3::hash(payload)!=header[48..80] {release(payload);return Frame{..},Error.invalid_artifact;}return Frame{kind:kind,id:get(header,16,8),inference_budget:get(header,40,8),bytes:payload,failure:failure,..},Error.none;
}
fn shutdown() {for live,index in alive {if live {blot_native::worker_stop(index as u32);alive[index]=false;}}}
fn run(kind:Kind,requests:const Request[:],requested_width:u8)->Replies,Error {
    if busy || worker_child {return Replies{..},Error.invalid_request;}if requests.len==0 {return Replies{..},Error.none;}if requested_width==0 || requested_width>worker_limit {return Replies{..},Error.invalid_request;}for request in requests {if request.bytes.len>packet_limit {return Replies{..},Error.artifact_limit;}}
    busy=true;let result,error=runBatch(kind,requests,requested_width);busy=false;if error!=Error.none {shutdown();}return result,error;
}
fn runBatch(kind:Kind,requests:const Request[:],requested_width:u8)->Replies,Error {
    var width=requested_width as i64;if width>requests.len {width=requests.len;}for index in width {if !alive[index] {if blot_native::worker_spawn(index as u32)<0 {return Replies{..},Error.io;}alive[index]=true;}}
    var result=Replies{items:reply_headers.alloc_slice(requests.len)};for &item in result.items {item=Reply{..};}var first:i64=0;
    while first<requests.len {
        var count=width;if count>requests.len-first {count=requests.len-first;}var ids:u64[16]=[0;16];
        for index in count {if next_request==0xffffffffffffffff {result.deinit();return Replies{..},Error.artifact_limit;}ids[index]=next_request;next_request++;let writer=blot_io::Writer{blot_native::worker_descriptor(index as u32,true)};let error=writeFrame(writer,kind,ids[index],requests[first+index].bytes,Error.none);if error!=Error.none {result.deinit();return Replies{..},error;}}
        var first_failure=Error.none;
        for index in count {let reader=blot_io::Reader{blot_native::worker_descriptor(index as u32,false)};var frame,error=readFrame(reader);if error!=Error.none {result.deinit();return Replies{..},error;}if frame.id!=ids[index] || frame.kind!=kind || frame.inference_budget!=inference_budget {frame.deinit();result.deinit();return Replies{..},Error.invalid_artifact;}result.items[first+index]=Reply{frame.bytes,frame.failure};frame.bytes=[];if frame.failure!=Error.none && first_failure==Error.none {first_failure=frame.failure;}}
        if first_failure!=Error.none {for index in first+count..requests.len {result.items[index].failure=first_failure;}shutdown();return result,Error.none;}first+=count;
    }return result,Error.none;
}
