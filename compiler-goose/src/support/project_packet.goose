// Process-local project/check/lower wire images. Only typed data crosses this
// boundary; owner leases, callbacks and references are rebuilt in the child.
namespace blot_project_packet;
import binary;
import support.error;
import support.native;
import support.option;
import support.bytes;
import check.types;
import check.parameter_patterns;
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
fn putOptional<T>(receiver:Writer&,value:T?) {put(receiver,value!=null);if value {let item:T=value;put(receiver,item);}}
fn readOptional<T>(receiver:Reader&,witness:T)->T? {var present=false;get(receiver,present);if receiver.failure!=blot_error::Error.none||!present {return null;}let run,error=allocate(receiver.owner,1,default<T>());if error!=blot_error::Error.none {receiver.failure=error;return null;}get(receiver,run[0]);if receiver.failure!=blot_error::Error.none {return null;}return run[0];}
fn put<K,V>(receiver:Writer&,value:dictionary_slot<K,V>) {put(receiver,value.tag);if value.tag!=0 {put(receiver,value.key);put(receiver,value.val);}}
fn get<K,V>(receiver:Reader&,value:dictionary_slot<K,V>&) {get(receiver,value.tag);if value.tag!=0 {get(receiver,value.key);get(receiver,value.val);}}

// A list is exactly two little-endian words. At the packet boundary the
// scalar codec can still complete the first word before the second fails.
fn put(writer: Writer&, value: blot_check_types::List) {
    if !writer.enter() { return; }
    if writer.output.len <= limit - 8 {
        let words = (value.len as u64 << 32) | value.start;
        var bytes: u8[8] = [0; 8];
        for index in 8 { bytes[index] = (words >> (index * 8)) as! u8; }
        writer.output.append(bytes);
    } else {
        put(writer, value.start);
        put(writer, value.len);
    }
    writer.depth--;
}
fn get(reader: Reader&, value: blot_check_types::List&) {
    if !reader.enter() { return; }
    if reader.at <= reader.bytes.len - 8 {
        let words = binary::u64le(reader.bytes, reader.at);
        value.start = words as! u32;
        value.len = (words >> 32) as u32;
        reader.at += 8;
    } else {
        get(reader, value.start);
        get(reader, value.len);
    }
    reader.depth--;
}

// These regular arrays use Goose's verified flat image. The parent and fork
// use the same executable and allocator layout.
fn putFlat<T>(receiver:Writer&,values:const T[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let payload=bytes_of(values).len;
    var width:i64=1;
    var rest=payload;
    while rest>=128 {width++;rest>>=7;}
    let size=payload+width;
    if !receiver.room(8+size) {return;}
    put(receiver,size as u64);
    to_bytes(values,receiver.output);
}
fn getFlat<T>(receiver:Reader&,value:T[:]& ) {
    let length=count(receiver);
    if receiver.failure!=blot_error::Error.none {return;}
    if length==0 {value=default<T[:]>();return;}
    var size:u64=0;
    get(receiver,size);
    if size>limit as u64 {receiver.failure=blot_error::Error.invalid_artifact;return;}
    let bytes=size as i64;
    if !receiver.available(bytes) {return;}
    let end=receiver.at+bytes;
    let values,valid=from_bytes<T[>..]>(receiver.bytes[receiver.at..end]);
    if !valid || values.len!=length {receiver.failure=blot_error::Error.invalid_artifact;return;}
    let run,error=allocate(receiver.owner,length,default<T>());
    if error!=blot_error::Error.none {receiver.failure=error;return;}
    run.move_from(values[..]);
    value=run;
    receiver.at=end;
}
