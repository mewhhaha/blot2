// Process-local project/check/lower wire images. Only typed data crosses this
// boundary; owner leases, callbacks and references are rebuilt in the child.
namespace blot_project_packet;
import support.error;
import support.native;
import support.option;
import support.bytes;
import .project_packet_owners;
import .project_packet_codecs;
import .project_packet_contexts;
type Error=blot_error::Error;
let limit:i64=536870912;
let element_limit:i64=67108864;
let depth_limit:i64=128;
struct Writer {output:u8[>..<]&,failure:Error=blot_error::Error.none,depth:i64=0}
struct Reader {bytes:const u8[:],owner:Owner,at:i64=0,failure:Error=blot_error::Error.none,remaining:i64=element_limit,depth:i64=0}
fn room(receiver:Writer&,amount:i64)->bool {if receiver.failure!=blot_error::Error.none {return false;}if amount<0||receiver.output.len>limit||amount>limit-receiver.output.len {receiver.failure=blot_error::Error.artifact_limit;return false;}return true;}
fn available(receiver:Reader&,amount:i64)->bool {if receiver.failure!=blot_error::Error.none {return false;}if amount<0||receiver.at>receiver.bytes.len||amount>receiver.bytes.len-receiver.at {receiver.failure=blot_error::Error.invalid_artifact;return false;}return true;}
fn enter(receiver:Writer&)->bool {if receiver.failure!=blot_error::Error.none {return false;}if receiver.depth>=depth_limit {receiver.failure=blot_error::Error.artifact_limit;return false;}receiver.depth++;return true;}
fn enter(receiver:Reader&)->bool {if receiver.failure!=blot_error::Error.none {return false;}if receiver.depth>=depth_limit {receiver.failure=blot_error::Error.artifact_limit;return false;}receiver.depth++;return true;}
fn put(receiver:Writer&,value:bool) {var bit:u8=0;if value {bit=1;}put(receiver,bit);}
fn get(receiver:Reader&,value:bool&) {var bit:u8=0;get(receiver,bit);if bit>1 {receiver.failure=blot_error::Error.invalid_artifact;return;}value=bit==1;}
fn count(receiver:Writer&,length:i64) {if length<0||length>element_limit {receiver.failure=blot_error::Error.artifact_limit;return;}put(receiver,length as u64);}
fn count(receiver:Reader&)->i64 {var length:u64=0;get(receiver,length);if receiver.failure!=blot_error::Error.none {return 0;}if length>receiver.remaining as u64||length>(receiver.bytes.len-receiver.at) as u64 {receiver.failure=blot_error::Error.artifact_limit;return 0;}receiver.remaining-=length as i64;return length as i64;}
fn put<T>(receiver:Writer&,value:const T[:]) {if !receiver.enter() {return;}count(receiver,value.len);for item in value {put(receiver,item);}receiver.depth--;}
fn get<T>(receiver:Reader&,value:T[:]& ) {if !receiver.enter() {return;}let length=count(receiver);if receiver.failure!=blot_error::Error.none {receiver.depth--;return;}let run,error=allocate(receiver.owner,length,default<T>());if error!=blot_error::Error.none {receiver.failure=error;receiver.depth--;return;}value=run;for &item in run {get(receiver,item);if receiver.failure!=blot_error::Error.none {break;}}receiver.depth--;}
fn get<T>(receiver:Reader&,value:(const T[:])&) {var run:T[:]=default<T[:]>();get(receiver,run);value=run;}
fn put<T>(receiver:Writer&,value:blot_support::Option<T>) {put(receiver,value.present);if value.present {put(receiver,value.value);}}
fn get<T>(receiver:Reader&,value:blot_support::Option<T>&) {get(receiver,value.present);if receiver.failure!=blot_error::Error.none {return;}if value.present {get(receiver,value.value);}}
fn put<T>(receiver:Writer&,value:T?) {put(receiver,value!=null);if value {let item:T=value;put(receiver,item);}}
fn readOptional<T>(receiver:Reader&,witness:T)->T? {var present=false;get(receiver,present);if receiver.failure!=blot_error::Error.none||!present {return null;}let run,error=allocate(receiver.owner,1,default<T>());if error!=blot_error::Error.none {receiver.failure=error;return null;}get(receiver,run[0]);if receiver.failure!=blot_error::Error.none {return null;}return run[0];}
fn put<K,V>(receiver:Writer&,value:dictionary_slot<K,V>) {put(receiver,value.tag);if value.tag!=0 {put(receiver,value.key);put(receiver,value.val);}}
fn get<K,V>(receiver:Reader&,value:dictionary_slot<K,V>&) {get(receiver,value.tag);if value.tag!=0 {get(receiver,value.key);get(receiver,value.val);}}
