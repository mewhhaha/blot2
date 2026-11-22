// Process-local project/check/lower wire images. Only typed data crosses this
// boundary; owner leases, callbacks and references are rebuilt in the child.
namespace blot_project_packet;
import binary;
import support.error;
import support.native;
import support.option;
import support.bytes;
import check.types;
import check.core;
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

// Direct byte and u32 slice codecs avoid temporary from_bytes allocations.
fn put(receiver:Writer&,values:const u8[:]) {
    count(receiver,values.len);
    if values.len==0 || !receiver.room(values.len) {return;}
    receiver.output.append(values);
}
fn get(receiver:Reader&,value:u8[:]&) {
    let length=count(receiver);
    if receiver.failure!=blot_error::Error.none {return;}
    if length==0 {value=default<u8[:]>();return;}
    if !receiver.available(length) {return;}
    let run,error=allocate(receiver.owner,length,0 as u8);
    if error!=blot_error::Error.none {receiver.failure=error;return;}
    run.move_from(receiver.bytes[receiver.at..receiver.at+length]);
    receiver.at+=length;
    value=run;
}
fn put(receiver:Writer&,values:const u32[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:u32[:]&) {
    let length=count(receiver);
    if receiver.failure!=blot_error::Error.none {return;}
    if length==0 {value=default<u32[:]>();return;}
    if length>limit/4 {receiver.failure=blot_error::Error.artifact_limit;return;}
    let byte_len=length*4;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,0 as u32);
    if error!=blot_error::Error.none {receiver.failure=error;return;}
    blot_native::copy_u32(run[0],receiver.bytes[receiver.at],length as u64);
    receiver.at+=byte_len;
    value=run;
}

// Only the Wasm preparation path sends this image. The parent resolves a
// constructor's signature in its defining module. Each importing module still
// needs its own catalog index, tag and payload type to interpret its Core.
fn putExecutionCore(writer:Writer&,module:blot_check_core::Module) {
    var header=module;
    header.constructors=default<blot_check_core::Constructor[:]>();
    put(writer,header);
    count(writer,module.constructors.len);
    for c in module.constructors {
        if !writer.room(24) {return;}
        let u=c.identity.unit;let d=c.identity.decl;let n=c.nominal;let t=c.tag;let p=c.payload;let nm=c.name;
        var buf:u8[24]=[
            u as! u8,(u>>8) as! u8,(u>>16) as! u8,(u>>24) as! u8,
            d as! u8,(d>>8) as! u8,(d>>16) as! u8,(d>>24) as! u8,
            n as! u8,(n>>8) as! u8,(n>>16) as! u8,(n>>24) as! u8,
            t as! u8,(t>>8) as! u8,(t>>16) as! u8,(t>>24) as! u8,
            p as! u8,(p>>8) as! u8,(p>>16) as! u8,(p>>24) as! u8,
            nm as! u8,(nm>>8) as! u8,(nm>>16) as! u8,(nm>>24) as! u8,
        ];
        writer.output.append(buf);
        if u==module.unit {put(writer,c.scheme);}
    }
}

fn getExecutionCore(reader:Reader&,module:blot_check_core::Module&) {
    get(reader,module);
    if reader.failure!=blot_error::Error.none {return;}
    if module.unit==0 || module.constructors.len!=0 {reader.failure=blot_error::Error.invalid_artifact;return;}
    let length=count(reader);
    if reader.failure!=blot_error::Error.none || !reader.available(length*24) {return;}
    let constructors,error=allocate(reader.owner,length,default<blot_check_core::Constructor>());
    if error!=blot_error::Error.none {reader.failure=error;return;}
    for &c in constructors {
        c=default<blot_check_core::Constructor>();
        if !reader.available(24) {return;}
        let at=reader.at;
        c.identity.unit=binary::u32le(reader.bytes,at);
        c.identity.decl=binary::u32le(reader.bytes,at+4);
        c.nominal=binary::u32le(reader.bytes,at+8);
        c.tag=binary::u32le(reader.bytes,at+12);
        c.payload=binary::u32le(reader.bytes,at+16);
        c.name=binary::u32le(reader.bytes,at+20);
        reader.at=at+24;
        if c.identity.unit==module.unit {
            get(reader,c.scheme);
            if reader.failure!=blot_error::Error.none {return;}
        }
    }
    module.constructors=constructors;
}
