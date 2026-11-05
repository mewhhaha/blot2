// BLOTDEP1 portable owners: no padding, pointers, capacities or solver caches.
namespace blot_reuse_dependency_format;
import support.error;
import support.option;
import support.blake3;
import support.native;
import .dependency_format_codecs;
import .dependency_format_owners;
import reuse.dependency_payload;
import reuse.frozen_dependency;
type Error=blot_error::Error;
type Digest=u8[32];
let magic:const u8[:]="BLOTDEP1";
let version:u32=5;
let header_size:i64=212;
struct Key {compiler:Digest,settings:Digest,source:Digest,dependencies:Digest}
struct Limits {payload_bytes:i64=67108864,elements:i64=4194304,depth:i64=64}
struct Owned<T> {value:T,owner:Owner=Owner{}}
reusable[] var encoded_bytes:u8[>..]=[];
fn release(bytes:u8[:]) {if bytes.len!=0 {encoded_bytes.free_slice(bytes);}}
fn deinit<T>(self_:Owned<T>&) {self_.owner.deinit();self_=default<Owned<T>>();}
fn digest(bytes:const u8[:])->Digest {return blot_support_blake3::hash(bytes);}
fn inspectKey(bytes:const u8[:])->Key,Error {
 if bytes.len<header_size || bytes[..8]!=magic {return default<Key>(),blot_error::Error.invalid_artifact;}var stored:u32=0;for index in 0..4 {stored|=(bytes[8+index] as u32)<<((index*8) as u32);}if stored!=version {return default<Key>(),blot_error::Error.unsupported_version;}
 var result=default<Key>();var at:i64=44;const for <N,A> in fields<Key> {for index in 0..32 {result.A[index]=bytes[at+index];}at+=32;}return result,blot_error::Error.none;
}
struct Encoder {out:u8[:]=default<u8[:]>(),writing:bool=false,len:i64=0,limits:Limits=Limits{},remaining:i64=0}
fn append(self_:Encoder&,bytes:const u8[:])->Error {if self_.len>self_.limits.payload_bytes || bytes.len>self_.limits.payload_bytes-self_.len {return blot_error::Error.artifact_limit;}if self_.writing {assert(self_.len<=self_.out.len && bytes.len<=self_.out.len-self_.len);for byte,index in bytes {self_.out[self_.len+index]=byte;}}self_.len+=bytes.len;return blot_error::Error.none;}
fn integer(self_:Encoder&,number:u64,width:i64)->Error {var bytes:u8[8];assert(width>0 && width<=8);for index in width {bytes[index]=(number>>((index*8) as u32)) as! u8;}return self_.append(bytes[..width]);}
fn varint_(self_:Encoder&,number:u64)->Error {var data:u8[10];var length:i64=0;var rest=number;while rest>=0x80 {data[length]=(rest as! u8)|0x80;length++;rest>>=7;}data[length]=rest as! u8;return self_.append(data[..length+1]);}
fn depth(self_:Encoder&,depth:i64)->Error {if depth>self_.limits.depth {return blot_error::Error.artifact_limit;}return blot_error::Error.none;}
struct Decoder<O> {owner:O&,bytes:const u8[:],limits:Limits,remaining:i64,at:i64=0}
fn take<O>(self_:Decoder<O>&,length:i64)->const u8[:],Error {if length<0 || self_.at>self_.bytes.len || length>self_.bytes.len-self_.at {return default<const u8[:]>(),blot_error::Error.invalid_artifact;}let result=self_.bytes[self_.at..self_.at+length];self_.at+=length;return result,blot_error::Error.none;}
fn integer<O>(self_:Decoder<O>&,width:i64)->u64,Error {let data,error=self_.take(width);if error!=blot_error::Error.none {return 0,error;}var result:u64=0;for byte,index in data {result|=(byte as u64)<<((index*8) as u32);}return result,blot_error::Error.none;}
fn varint_<O>(self_:Decoder<O>&)->u64,Error {
 var result:u64=0;var shift:u32=0;loop {if self_.at==self_.bytes.len || shift>63 {return 0,blot_error::Error.invalid_artifact;}let byte=self_.bytes[self_.at];self_.at++;let bits=(byte&0x7f) as u64;if shift==63 && bits>1 {return 0,blot_error::Error.invalid_artifact;}result|=bits<<shift;if (byte&0x80)==0 {if byte==0 && shift!=0 {return 0,blot_error::Error.invalid_artifact;}return result,blot_error::Error.none;}shift+=7;}
}
fn depth<O>(self_:Decoder<O>&,depth:i64)->Error {if depth>self_.limits.depth {return blot_error::Error.artifact_limit;}return blot_error::Error.none;}
fn zigzag(number:i64)->u64 {var sign:u64=0;if number<0 {sign=0xffffffffffffffff;}return ((number as! u64)<<1)^sign;}
fn unzigzag(raw:u64)->i64 {let half=(raw>>1) as i64;if (raw&1)!=0 {return -half-1;}return half;}
fn encode<T>(key:Key,value:T)->u8[:],Error {return encodeWithLimits(key,value,Limits{});}
fn encodeWithLimits<T>(key:Key,value:T,limits:Limits)->u8[:],Error {
 var counter=Encoder{limits:limits,remaining:limits.elements};let error=writeValue(counter,value,0);if error!=blot_error::Error.none {return default<u8[:]>(),error;}if counter.len>0x7fffffffffffffff-header_size {return default<u8[:]>(),blot_error::Error.artifact_limit;}
 let output=encoded_bytes.alloc_slice(header_size+counter.len);var published=false;
 var body=Encoder{out:output[header_size..],writing:true,limits:limits,remaining:limits.elements};let error=writeValue(body,value,0);if error!=blot_error::Error.none {let __cleanup_result_1_0: u8[:] = default<u8[:]>(); let __cleanup_result_1_1: Error = error; {if !published {release(output);}} return __cleanup_result_1_0, __cleanup_result_1_1;}assert(body.len==counter.len);
 var header=Encoder{out:output[..header_size],writing:true,limits:Limits{payload_bytes:header_size},remaining:1024};let error=header.append(magic);if error!=blot_error::Error.none {let __cleanup_result_2_0: u8[:] = default<u8[:]>(); let __cleanup_result_2_1: Error = error; {if !published {release(output);}} return __cleanup_result_2_0, __cleanup_result_2_1;}let error=header.integer(version as u64,4);if error!=blot_error::Error.none {let __cleanup_result_3_0: u8[:] = default<u8[:]>(); let __cleanup_result_3_1: Error = error; {if !published {release(output);}} return __cleanup_result_3_0, __cleanup_result_3_1;}
 let schema_digest=schema(value);let error=writeValue(header,schema_digest,0);if error!=blot_error::Error.none {let __cleanup_result_4_0: u8[:] = default<u8[:]>(); let __cleanup_result_4_1: Error = error; {if !published {release(output);}} return __cleanup_result_4_0, __cleanup_result_4_1;}let error=writeValue(header,key,0);if error!=blot_error::Error.none {let __cleanup_result_5_0: u8[:] = default<u8[:]>(); let __cleanup_result_5_1: Error = error; {if !published {release(output);}} return __cleanup_result_5_0, __cleanup_result_5_1;}let error=header.integer(counter.len as u64,8);if error!=blot_error::Error.none {let __cleanup_result_6_0: u8[:] = default<u8[:]>(); let __cleanup_result_6_1: Error = error; {if !published {release(output);}} return __cleanup_result_6_0, __cleanup_result_6_1;}let error=writeValue(header,digest(output[header_size..]),0);if error!=blot_error::Error.none {let __cleanup_result_7_0: u8[:] = default<u8[:]>(); let __cleanup_result_7_1: Error = error; {if !published {release(output);}} return __cleanup_result_7_0, __cleanup_result_7_1;}assert(header.len==header_size);published=true;let __cleanup_result_8_0: u8[:] = output; let __cleanup_result_8_1: Error = blot_error::Error.none; {if !published {release(output);}} return __cleanup_result_8_0, __cleanup_result_8_1;
 {if !published {release(output);}} }
fn decode<T>(bytes:const u8[:],expected:Key)->Owned<T>,Error {return decodeWithLimits<T>(bytes,expected,Limits{});}
fn decodeWithLimits<T>(bytes:const u8[:],expected:Key,limits:Limits)->Owned<T>,Error {
 let opened,error=initOwner();if error!=blot_error::Error.none {return default<Owned<T>>(),error;}var owner=opened;let value,error=decodeInto<T,Owner>(owner,bytes,expected,limits);if error!=blot_error::Error.none {owner.deinit();return default<Owned<T>>(),error;}return Owned<T>{value,owner},blot_error::Error.none;
}
fn decodeInto<T,O>(owner:O&,bytes:const u8[:],expected:Key,limits:Limits=Limits{})->T,Error {
 if bytes.len<header_size || bytes[..8]!=magic {return default<T>(),blot_error::Error.invalid_artifact;}let mark=owner.mark();var committed=false;
 var reader=Decoder<O>{owner:owner,bytes:bytes,limits:limits,remaining:limits.elements,at:8};let stored_version,error=reader.integer(4);if error!=blot_error::Error.none {let __cleanup_result_9_0: T = default<T>(); let __cleanup_result_9_1: Error = error; {if !committed {owner.rollback(mark);}} return __cleanup_result_9_0, __cleanup_result_9_1;}if stored_version!=version {let __cleanup_result_10_0: T = default<T>(); let __cleanup_result_10_1: Error = blot_error::Error.unsupported_version; {if !committed {owner.rollback(mark);}} return __cleanup_result_10_0, __cleanup_result_10_1;}
 let stored_schema,error=readValue(reader,default<Digest>(),0);if error!=blot_error::Error.none {let __cleanup_result_11_0: T = default<T>(); let __cleanup_result_11_1: Error = error; {if !committed {owner.rollback(mark);}} return __cleanup_result_11_0, __cleanup_result_11_1;}if stored_schema!=schema(default<T>()) {let __cleanup_result_12_0: T = default<T>(); let __cleanup_result_12_1: Error = blot_error::Error.schema_mismatch; {if !committed {owner.rollback(mark);}} return __cleanup_result_12_0, __cleanup_result_12_1;}
 let stored,error=readValue(reader,default<Key>(),0);if error!=blot_error::Error.none {let __cleanup_result_13_0: T = default<T>(); let __cleanup_result_13_1: Error = error; {if !committed {owner.rollback(mark);}} return __cleanup_result_13_0, __cleanup_result_13_1;}const for <N,A> in fields<Key> {if stored.A!=expected.A {let __cleanup_result_14_0: T = default<T>(); let __cleanup_result_14_1: Error = blot_error::Error.stale_artifact; {if !committed {owner.rollback(mark);}} return __cleanup_result_14_0, __cleanup_result_14_1;}}
 let size,error=reader.integer(8);if error!=blot_error::Error.none {let __cleanup_result_15_0: T = default<T>(); let __cleanup_result_15_1: Error = error; {if !committed {owner.rollback(mark);}} return __cleanup_result_15_0, __cleanup_result_15_1;}let checksum,error=readValue(reader,default<Digest>(),0);if error!=blot_error::Error.none {let __cleanup_result_16_0: T = default<T>(); let __cleanup_result_16_1: Error = error; {if !committed {owner.rollback(mark);}} return __cleanup_result_16_0, __cleanup_result_16_1;}
 if limits.payload_bytes<0 || size>limits.payload_bytes as u64 {let __cleanup_result_17_0: T = default<T>(); let __cleanup_result_17_1: Error = blot_error::Error.artifact_limit; {if !committed {owner.rollback(mark);}} return __cleanup_result_17_0, __cleanup_result_17_1;}if size!=(bytes.len-header_size) as u64 {let __cleanup_result_18_0: T = default<T>(); let __cleanup_result_18_1: Error = blot_error::Error.invalid_artifact; {if !committed {owner.rollback(mark);}} return __cleanup_result_18_0, __cleanup_result_18_1;}if checksum!=digest(bytes[header_size..]) {let __cleanup_result_19_0: T = default<T>(); let __cleanup_result_19_1: Error = blot_error::Error.invalid_artifact; {if !committed {owner.rollback(mark);}} return __cleanup_result_19_0, __cleanup_result_19_1;}
 reader.remaining=limits.elements;let value,error=readValue(reader,default<T>(),0);if error!=blot_error::Error.none {let __cleanup_result_20_0: T = default<T>(); let __cleanup_result_20_1: Error = error; {if !committed {owner.rollback(mark);}} return __cleanup_result_20_0, __cleanup_result_20_1;}if reader.at!=bytes.len {let __cleanup_result_21_0: T = default<T>(); let __cleanup_result_21_1: Error = blot_error::Error.invalid_artifact; {if !committed {owner.rollback(mark);}} return __cleanup_result_21_0, __cleanup_result_21_1;}committed=true;let __cleanup_result_22_0: T = value; let __cleanup_result_22_1: Error = blot_error::Error.none; {if !committed {owner.rollback(mark);}} return __cleanup_result_22_0, __cleanup_result_22_1;
 {if !committed {owner.rollback(mark);}} }
// Source-authored concrete metadata preserves the native type spellings, enum
// values and wire fields. Runtime reflection never hashes Goose owner metadata.
fn schema<T>(value:T)->Digest {var hasher=blot_support_blake3::init();describe(hasher,value);return blot_support_blake3::final(hasher);}

fn decodeWithOwner<T>(owner:Owner&,bytes:const u8[:],expected:Key,limits:Limits=Limits{})->T,Error {return decodeInto<T,Owner>(owner,bytes,expected,limits);}
fn decodeWithOwner<T>(owner:blot_reuse_dependency_payload::Owner&,bytes:const u8[:],expected:Key,limits:Limits=Limits{})->T,Error {return decodeInto<T,blot_reuse_dependency_payload::Owner>(owner,bytes,expected,limits);}
fn decodeWithOwner<T,O>(owner:O&,bytes:const u8[:],expected:Key,limits:Limits=Limits{})->T,Error {return decodeInto<T,O>(owner,bytes,expected,limits);}
fn encodeFrozen(key:Key,value:blot_reuse_frozen_dependency::FrozenDependency)->u8[:],Error {return encode(key,value);}
