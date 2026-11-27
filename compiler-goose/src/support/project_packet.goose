// Process-local project/check/lower wire images. Only typed data crosses this
// boundary; owner leases, callbacks and references are rebuilt in the child.
namespace squid_project_packet;
import binary;
import support.error;
import support.native;
import support.option;
import support.bytes;
import parse.ast;
import check.types;
import check.core;
import check.parameter_patterns;
import .project_packet_owners;
import .project_packet_codecs;
import .project_packet_contexts;
type Error=squid_error::Error;
let limit:i64=536870912;
let element_limit:i64=67108864;
let depth_limit:i64=128;
struct Writer {output:u8[>..<]&,failure:Error=squid_error::Error.none,depth:i64=0}
struct Reader {bytes:const u8[:],owner:Owner,at:i64=0,failure:Error=squid_error::Error.none,remaining:i64=element_limit,depth:i64=0}
fn room(receiver:Writer&,amount:i64)->bool {if receiver.failure!=squid_error::Error.none {return false;}if amount<0||receiver.output.len>limit||amount>limit-receiver.output.len {receiver.failure=squid_error::Error.artifact_limit;return false;}return true;}
fn available(receiver:Reader&,amount:i64)->bool {if receiver.failure!=squid_error::Error.none {return false;}if amount<0||receiver.at>receiver.bytes.len||amount>receiver.bytes.len-receiver.at {receiver.failure=squid_error::Error.invalid_artifact;return false;}return true;}
fn enter(receiver:Writer&)->bool {if receiver.failure!=squid_error::Error.none {return false;}if receiver.depth>=depth_limit {receiver.failure=squid_error::Error.artifact_limit;return false;}receiver.depth++;return true;}
fn enter(receiver:Reader&)->bool {if receiver.failure!=squid_error::Error.none {return false;}if receiver.depth>=depth_limit {receiver.failure=squid_error::Error.artifact_limit;return false;}receiver.depth++;return true;}
fn put(receiver:Writer&,value:bool) {var bit:u8=0;if value {bit=1;}put(receiver,bit);}
fn get(receiver:Reader&,value:bool&) {var bit:u8=0;get(receiver,bit);if bit>1 {receiver.failure=squid_error::Error.invalid_artifact;return;}value=bit==1;}
fn count(receiver:Writer&,length:i64) {if length<0||length>element_limit {receiver.failure=squid_error::Error.artifact_limit;return;}put(receiver,length as u64);}
fn count(receiver:Reader&)->i64 {var length:u64=0;get(receiver,length);if receiver.failure!=squid_error::Error.none {return 0;}if length>receiver.remaining as u64||length>(receiver.bytes.len-receiver.at) as u64 {receiver.failure=squid_error::Error.artifact_limit;return 0;}receiver.remaining-=length as i64;return length as i64;}
fn put<T>(receiver:Writer&,value:const T[:]) {if !receiver.enter() {return;}count(receiver,value.len);for item in value {put(receiver,item);}receiver.depth--;}
fn get<T>(receiver:Reader&,value:T[:]& ) {if !receiver.enter() {return;}let length=count(receiver);if receiver.failure!=squid_error::Error.none {receiver.depth--;return;}let run,error=allocate(receiver.owner,length,default<T>());if error!=squid_error::Error.none {receiver.failure=error;receiver.depth--;return;}value=run;for &item in run {get(receiver,item);if receiver.failure!=squid_error::Error.none {break;}}receiver.depth--;}
fn get<T>(receiver:Reader&,value:(const T[:])&) {var run:T[:]=default<T[:]>();get(receiver,run);value=run;}
fn put<T>(receiver:Writer&,value:squid_support::Option<T>) {put(receiver,value.present);if value.present {put(receiver,value.value);}}
fn get<T>(receiver:Reader&,value:squid_support::Option<T>&) {get(receiver,value.present);if receiver.failure!=squid_error::Error.none {return;}if value.present {get(receiver,value.value);}}
fn putOptional<T>(receiver:Writer&,value:T?) {put(receiver,value!=null);if value {let item:T=value;put(receiver,item);}}
fn readOptional<T>(receiver:Reader&,witness:T)->T? {var present=false;get(receiver,present);if receiver.failure!=squid_error::Error.none||!present {return null;}let run,error=allocate(receiver.owner,1,default<T>());if error!=squid_error::Error.none {receiver.failure=error;return null;}get(receiver,run[0]);if receiver.failure!=squid_error::Error.none {return null;}return run[0];}
fn put<K,V>(receiver:Writer&,value:dictionary_slot<K,V>) {put(receiver,value.tag);if value.tag!=0 {put(receiver,value.key);put(receiver,value.val);}}
fn get<K,V>(receiver:Reader&,value:dictionary_slot<K,V>&) {get(receiver,value.tag);if value.tag!=0 {get(receiver,value.key);get(receiver,value.val);}}

// A list is exactly two little-endian words. At the packet boundary the
// scalar codec can still complete the first word before the second fails.
fn put(writer: Writer&, value: squid_check_types::List) {
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
fn get(reader: Reader&, value: squid_check_types::List&) {
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
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<T[:]>();return;}
    var size:u64=0;
    get(receiver,size);
    if size>limit as u64 {receiver.failure=squid_error::Error.invalid_artifact;return;}
    let bytes=size as i64;
    if !receiver.available(bytes) {return;}
    let end=receiver.at+bytes;
    let values,valid=from_bytes<T[>..]>(receiver.bytes[receiver.at..end]);
    if !valid || values.len!=length {receiver.failure=squid_error::Error.invalid_artifact;return;}
    let run,error=allocate(receiver.owner,length,default<T>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    run.move_from(values[..]);
    value=run;
    receiver.at=end;
}
fn putRawFlat<T>(receiver:Writer&,values:const T[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn getRawFlat<T>(receiver:Reader&,value:T[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<T[:]>();return;}
    var sample:T[1]=[default<T>()];
    let elem_size=bytes_of(sample[..]).len;
    if elem_size<=0 || length>limit/elem_size {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*elem_size;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<T>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    let dst=bytes_of(run);
    assert(dst.len==byte_len);
    squid_native::copy_flat(dst[0],receiver.bytes[receiver.at],byte_len as u64);
    receiver.at+=byte_len;
    value=run;
}

// Direct byte and u32 slice codecs avoid temporary from_bytes allocations.
fn put(receiver:Writer&,values:const u8[:]) {
    count(receiver,values.len);
    if values.len==0 || !receiver.room(values.len) {return;}
    receiver.output.append(values);
}
fn get(receiver:Reader&,value:u8[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<u8[:]>();return;}
    if !receiver.available(length) {return;}
    let run,error=allocate(receiver.owner,length,0 as u8);
    if error!=squid_error::Error.none {receiver.failure=error;return;}
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
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<u32[:]>();return;}
    if length>limit/4 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*4;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,0 as u32);
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    squid_native::copy_u32(run[0],receiver.bytes[receiver.at],length as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_parse_ast::Span[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_parse_ast::Span[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_parse_ast::Span[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_parse_ast::Span>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].start,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::List[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::List[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::List[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::List>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].start,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_types::List[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_types::List[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_types::List[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_types::List>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].start,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::BindingRef[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::BindingRef[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::BindingRef[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::BindingRef>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].unit,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::CallInfo[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::CallInfo[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::CallInfo[:]>();return;}
    if length>limit/16 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*16;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::CallInfo>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].target.unit,receiver.bytes[receiver.at],(length*4) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::FieldName[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::FieldName[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::FieldName[:]>();return;}
    if length>limit/12 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*12;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::FieldName>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].symbol,receiver.bytes[receiver.at],(length*3) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::RuntimeName[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::RuntimeName[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::RuntimeName[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::RuntimeName>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].binding,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::Merge[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::Merge[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::Merge[:]>();return;}
    if length>limit/16 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*16;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::Merge>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].node,receiver.bytes[receiver.at],(length*4) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::LoopCarry[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::LoopCarry[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::LoopCarry[:]>();return;}
    if length>limit/16 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*16;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::LoopCarry>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].incoming,receiver.bytes[receiver.at],(length*4) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::ProjectionVariant[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::ProjectionVariant[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::ProjectionVariant[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::ProjectionVariant>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].tag,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::PatternRow[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::PatternRow[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::PatternRow[:]>();return;}
    if length>limit/8 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*8;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::PatternRow>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].patterns.start,receiver.bytes[receiver.at],(length*2) as u64);
    receiver.at+=byte_len;
    value=run;
}
fn put(receiver:Writer&,values:const squid_check_core::HandleEffects[:]) {
    count(receiver,values.len);
    if values.len==0 {return;}
    let raw=bytes_of(values);
    if !receiver.room(raw.len) {return;}
    receiver.output.append(raw);
}
fn get(receiver:Reader&,value:squid_check_core::HandleEffects[:]&) {
    let length=count(receiver);
    if receiver.failure!=squid_error::Error.none {return;}
    if length==0 {value=default<squid_check_core::HandleEffects[:]>();return;}
    if length>limit/20 {receiver.failure=squid_error::Error.artifact_limit;return;}
    let byte_len=length*20;
    if !receiver.available(byte_len) {return;}
    let run,error=allocate(receiver.owner,length,default<squid_check_core::HandleEffects>());
    if error!=squid_error::Error.none {receiver.failure=error;return;}
    assert(bytes_of(run).len==byte_len);
    squid_native::copy_u32(run[0].node,receiver.bytes[receiver.at],(length*5) as u64);
    receiver.at+=byte_len;
    value=run;
}

// Split execution Core wire layout:
//   [0..64]            prefix_len: u32, followed by 15 bulk table byte lengths (u32 each)
//   [64..64+prefix]    compact header (Core without bulk/stripped slices, constructors, metadata)
//   [64+prefix..end]   15 bulk flat tables concatenated raw for zero-double-copy persist_read_at.
let execution_core_header_bytes:i64=64;

fn writeU32LeAt(buf:u8[>..<]&,at:i64,v:u32) {
    buf[at]=v as! u8;
    buf[at+1]=(v>>8) as! u8;
    buf[at+2]=(v>>16) as! u8;
    buf[at+3]=(v>>24) as! u8;
}

fn appendExecutionTable<T>(writer:Writer&,values:const T[:])->u32,bool {
    if values.len==0 {return 0,true;}
    let raw=bytes_of(values);
    if raw.len>0xffffffff || !writer.room(raw.len) {return 0,false;}
    writer.output.append(raw);
    return raw.len as u32,true;
}

fn putExecutionCoreHeader(writer:Writer&,module:squid_check_core::Module) {
    var header=module;
    header.constructors=default<squid_check_core::Constructor[:]>();
    header.runtime_names=default<squid_check_core::RuntimeName[:]>();
    header.source_names=default<squid_check_core::RuntimeName[:]>();
    header.declaration_dependencies=default<squid_check_core::DeclarationDependencies[:]>();
    header.dependency_references=default<squid_check_core::BindingRef[:]>();
    header.dependency_members=default<squid_check_core::DependencyMember[:]>();
    header.erased_declaration_references=default<squid_check_core::ErasedDeclarationReference[:]>();
    // The 15 bulk tables are appended raw after the prefix.
    header.nodes=default<squid_check_core::Node[:]>();
    header.spans=default<squid_check_core::Span[:]>();
    header.extra=default<squid_check_core::Id[:]>();
    header.bindings=default<squid_check_core::Binding[:]>();
    header.bodies=default<squid_check_core::Body[:]>();
    header.parameters=default<squid_check_core::Parameter[:]>();
    header.references=default<squid_check_core::BindingRef[:]>();
    header.calls=default<squid_check_core::CallInfo[:]>();
    header.names=default<u8[:]>();
    header.types.nodes=default<const squid_check_types::Node[:]>();
    header.types.extra=default<const squid_check_types::Id[:]>();
    header.patterns=default<squid_check_core::Pattern[:]>();
    header.obligations=default<squid_check_core::Obligation[:]>();
    header.merges=default<squid_check_core::Merge[:]>();
    header.merge_ranges=default<squid_check_core::List[:]>();
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

fn putExecutionCoreTables(writer:Writer&,module:squid_check_core::Module) {
    if writer.failure!=squid_error::Error.none {return;}
    let prefix_len=writer.output.len-execution_core_header_bytes;
    if prefix_len<0 || prefix_len>0xffffffff {writer.failure=squid_error::Error.artifact_limit;return;}
    writeU32LeAt(writer.output,0,prefix_len as u32);
    var lens:u32[15]=[0;15];
    var ok=true;
    if ok {let l,s=appendExecutionTable(writer,module.nodes);lens[0]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.spans);lens[1]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.extra);lens[2]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.bindings);lens[3]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.bodies);lens[4]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.parameters);lens[5]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.references);lens[6]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.calls);lens[7]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.names);lens[8]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.types.nodes);lens[9]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.types.extra);lens[10]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.patterns);lens[11]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.obligations);lens[12]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.merges);lens[13]=l;ok=s;}
    if ok {let l,s=appendExecutionTable(writer,module.merge_ranges);lens[14]=l;ok=s;}
    if !ok {if writer.failure==squid_error::Error.none {writer.failure=squid_error::Error.artifact_limit;}return;}
    for i in 0..15 {writeU32LeAt(writer.output,4+i*4,lens[i]);}
}

fn getExecutionCoreHeader(reader:Reader&,module:squid_check_core::Module&) {
    get(reader,module);
    if reader.failure!=squid_error::Error.none {return;}
    if module.unit==0 || module.constructors.len!=0 {reader.failure=squid_error::Error.invalid_artifact;return;}
    let length=count(reader);
    if reader.failure!=squid_error::Error.none || !reader.available(length*24) {return;}
    let constructors,error=allocate(reader.owner,length,default<squid_check_core::Constructor>());
    if error!=squid_error::Error.none {reader.failure=error;return;}
    for &c in constructors {
        c=default<squid_check_core::Constructor>();
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
            if reader.failure!=squid_error::Error.none {return;}
        }
    }
    module.constructors=constructors;
}

fn readPersistTable<T>(shared:u64,id:u32,kind:u32,at:i64&,total:i64,byte_len:i64,owner:Owner,witness:T)->T[:],Error {
    if byte_len==0 {return default<T[:]>(),squid_error::Error.none;}
    if byte_len<0 || byte_len>total-at || byte_len>limit {return default<T[:]>(),squid_error::Error.invalid_artifact;}
    var sample:T[1]=[witness];
    let elem_size=bytes_of(sample[..]).len;
    if elem_size<=0 || byte_len%elem_size!=0 {return default<T[:]>(),squid_error::Error.invalid_artifact;}
    let count=byte_len/elem_size;
    if count>element_limit {return default<T[:]>(),squid_error::Error.artifact_limit;}
    let run,error=allocate(owner,count,witness);
    if error!=squid_error::Error.none {return default<T[:]>(),error;}
    let dst=bytes_of(run);
    assert(dst.len==byte_len);
    if !squid_native::persist_read_at(shared,id,kind,at as u64,dst[0],byte_len as u64) {return default<T[:]>(),squid_error::Error.invalid_artifact;}
    at+=byte_len;
    return run,squid_error::Error.none;
}

fn getExecutionCoreTablesFromPersist(shared:u64,id:u32,kind:u32,at:i64&,total:i64,lens:const i64[:],owner:Owner,module:squid_check_core::Module&)->Error {
    let nodes,e0=readPersistTable(shared,id,kind,at,total,lens[0],owner,default<squid_check_core::Node>());if e0!=squid_error::Error.none {return e0;}module.nodes=nodes;
    let spans,e1=readPersistTable(shared,id,kind,at,total,lens[1],owner,default<squid_check_core::Span>());if e1!=squid_error::Error.none {return e1;}module.spans=spans;
    let extra,e2=readPersistTable(shared,id,kind,at,total,lens[2],owner,0 as u32);if e2!=squid_error::Error.none {return e2;}module.extra=extra;
    let bindings,e3=readPersistTable(shared,id,kind,at,total,lens[3],owner,default<squid_check_core::Binding>());if e3!=squid_error::Error.none {return e3;}module.bindings=bindings;
    let bodies,e4=readPersistTable(shared,id,kind,at,total,lens[4],owner,default<squid_check_core::Body>());if e4!=squid_error::Error.none {return e4;}module.bodies=bodies;
    let parameters,e5=readPersistTable(shared,id,kind,at,total,lens[5],owner,default<squid_check_core::Parameter>());if e5!=squid_error::Error.none {return e5;}module.parameters=parameters;
    let references,e6=readPersistTable(shared,id,kind,at,total,lens[6],owner,default<squid_check_core::BindingRef>());if e6!=squid_error::Error.none {return e6;}module.references=references;
    let calls,e7=readPersistTable(shared,id,kind,at,total,lens[7],owner,default<squid_check_core::CallInfo>());if e7!=squid_error::Error.none {return e7;}module.calls=calls;
    let names,e8=readPersistTable(shared,id,kind,at,total,lens[8],owner,0 as u8);if e8!=squid_error::Error.none {return e8;}module.names=names;
    let tnodes,e9=readPersistTable(shared,id,kind,at,total,lens[9],owner,default<squid_check_types::Node>());if e9!=squid_error::Error.none {return e9;}module.types.nodes=tnodes;
    let textra,e10=readPersistTable(shared,id,kind,at,total,lens[10],owner,0 as u32);if e10!=squid_error::Error.none {return e10;}module.types.extra=textra;
    let patterns,e11=readPersistTable(shared,id,kind,at,total,lens[11],owner,default<squid_check_core::Pattern>());if e11!=squid_error::Error.none {return e11;}module.patterns=patterns;
    let obligations,e12=readPersistTable(shared,id,kind,at,total,lens[12],owner,default<squid_check_core::Obligation>());if e12!=squid_error::Error.none {return e12;}module.obligations=obligations;
    let merges,e13=readPersistTable(shared,id,kind,at,total,lens[13],owner,default<squid_check_core::Merge>());if e13!=squid_error::Error.none {return e13;}module.merges=merges;
    let merge_ranges,e14=readPersistTable(shared,id,kind,at,total,lens[14],owner,default<squid_check_core::List>());if e14!=squid_error::Error.none {return e14;}module.merge_ranges=merge_ranges;
    if at!=total {return squid_error::Error.invalid_artifact;}
    return squid_error::Error.none;
}
