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
struct Writer {output:u8[>..<]&,failure:Error=Error.none,depth:i64=0}
struct Reader {bytes:const u8[:],owner:Owner,at:i64=0,failure:Error=Error.none,remaining:i64=element_limit,depth:i64=0}
fn room(self:Writer&,amount:i64)->bool {if self.failure!=Error.none {return false;}if amount<0||self.output.len>limit||amount>limit-self.output.len {self.failure=Error.artifact_limit;return false;}return true;}
fn available(self:Reader&,amount:i64)->bool {if self.failure!=Error.none {return false;}if amount<0||self.at>self.bytes.len||amount>self.bytes.len-self.at {self.failure=Error.invalid_artifact;return false;}return true;}
fn enter(self:Writer&)->bool {if self.failure!=Error.none {return false;}if self.depth>=depth_limit {self.failure=Error.artifact_limit;return false;}self.depth++;return true;}
fn enter(self:Reader&)->bool {if self.failure!=Error.none {return false;}if self.depth>=depth_limit {self.failure=Error.artifact_limit;return false;}self.depth++;return true;}
fn put(self:Writer&,value:bool) {var bit:u8=0;if value {bit=1;}put(self,bit);}
fn get(self:Reader&,value:bool&) {var bit:u8=0;get(self,bit);if bit>1 {self.failure=Error.invalid_artifact;return;}value=bit==1;}
fn count(self:Writer&,length:i64) {if length<0||length>element_limit {self.failure=Error.artifact_limit;return;}put(self,length as u64);}
fn count(self:Reader&)->i64 {var length:u64=0;get(self,length);if self.failure!=Error.none {return 0;}if length>self.remaining as u64||length>(self.bytes.len-self.at) as u64 {self.failure=Error.artifact_limit;return 0;}self.remaining-=length as i64;return length as i64;}
fn put<T>(self:Writer&,value:const T[:]) {if !self.enter() {return;}count(self,value.len);for item in value {put(self,item);}self.depth--;}
fn put<T>(self:Writer&,value:T[:]) {let values:const T[:]=value;put(self,values);}
fn get<T>(self:Reader&,value:T[:]& ) {if !self.enter() {return;}let length=count(self);if self.failure!=Error.none {self.depth--;return;}let run,error=self.owner.alloc<T>(length);if error!=Error.none {self.failure=error;self.depth--;return;}value=run;for &item in run {get(self,item);if self.failure!=Error.none {break;}}self.depth--;}
fn get<T>(self:Reader&,value:(const T[:])&) {var run:T[:]=[];get(self,run);value=run;}
fn put<T>(self:Writer&,value:blot_support::Option<T>) {put(self,value.present);if value.present {put(self,value.value);}}
fn get<T>(self:Reader&,value:blot_support::Option<T>&) {get(self,value.present);if self.failure!=Error.none {return;}if value.present {get(self,value.value);}}
fn put<T>(self:Writer&,value:T?) {put(self,value!=null);if value {let item:T=value;put(self,item);}}
fn get<T>(self:Reader&,value:(T?)&) {var present=false;get(self,present);if self.failure!=Error.none||!present {value .= null;return;}let run,error=self.owner.alloc<T>(1);if error!=Error.none {self.failure=error;return;}get(self,run[0]);if self.failure!=Error.none {value .= null;return;}value .= run[0];}
fn put<T>(self:Writer&,value:T) {if !self.enter() {return;}const for <N,A> in fields<T> {put(self,value.A);}self.depth--;}
fn get<T>(self:Reader&,value:T&) {if !self.enter() {return;}const for <N,A> in fields<T> {get(self,value.A);}self.depth--;}
fn put<K,V>(self:Writer&,value:dictionary_slot<K,V>) {put(self,value.tag);if value.tag!=0 {put(self,value.key);put(self,value.value);}}
fn get<K,V>(self:Reader&,value:dictionary_slot<K,V>&) {get(self,value.tag);if value.tag!=0 {get(self,value.key);get(self,value.value);}}
