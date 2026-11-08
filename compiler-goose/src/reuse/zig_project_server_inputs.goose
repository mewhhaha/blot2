// Strict JSON inputs own every decoded string and vector independently.
namespace blot_reuse_zig_project_server;
import .zig_project_server;
import json;
import dictionary;
type TextSlice=const u8[:];
enum JsonRun {bytes{values:u8[:]},aliases{values:blot_reuse_project::Alias[:]},ranges{values:SourceRange[:]},definitions{values:blot_backend_native_assets::Definition[:]},roots{values:TextSlice[:]}}
struct JsonLink {run:JsonRun,next:u32=0}
reusable var json_links:JsonLink[>..]=[];
struct JsonOwner {head:u32=0}
struct ParsedRequest {value:Request=default<Request>(),owner:JsonOwner=JsonOwner{..}}
fn remember(self_:JsonOwner&,run:JsonRun)->Error {if json_links.len>=0xffffffff {return blot_error::Error.out_of_memory;}let at=json_links.alloc_index(JsonLink{run,self_.head});self_.head=(at+1) as u32;return blot_error::Error.none;}
reusable[] var json_bytes:u8[>..]=[];
fn allocate(self_:JsonOwner&,sample:u8,count:i64)->u8[:],Error {if count<0 || count>67108864 {return default<u8[:]>(),blot_error::Error.source_limit;}if count==0 {return default<u8[:]>(),blot_error::Error.none;}let values=json_bytes.alloc_slice(count);let error=self_.remember(JsonRun.bytes{values});if error!=blot_error::Error.none {json_bytes.free_slice(values);return default<u8[:]>(),error;}return values,blot_error::Error.none;}
reusable[] var json_aliases:blot_reuse_project::Alias[>..]=[];
fn allocate(self_:JsonOwner&,sample:blot_reuse_project::Alias,count:i64)->blot_reuse_project::Alias[:],Error {if count<0 || count>67108864 {return default<blot_reuse_project::Alias[:]>(),blot_error::Error.source_limit;}if count==0 {return default<blot_reuse_project::Alias[:]>(),blot_error::Error.none;}let values=json_aliases.alloc_slice(count);let error=self_.remember(JsonRun.aliases{values});if error!=blot_error::Error.none {json_aliases.free_slice(values);return default<blot_reuse_project::Alias[:]>(),error;}return values,blot_error::Error.none;}
reusable[] var json_ranges:SourceRange[>..]=[];
fn allocate(self_:JsonOwner&,sample:SourceRange,count:i64)->SourceRange[:],Error {if count<0 || count>67108864 {return default<SourceRange[:]>(),blot_error::Error.source_limit;}if count==0 {return default<SourceRange[:]>(),blot_error::Error.none;}let values=json_ranges.alloc_slice(count);let error=self_.remember(JsonRun.ranges{values});if error!=blot_error::Error.none {json_ranges.free_slice(values);return default<SourceRange[:]>(),error;}return values,blot_error::Error.none;}
reusable[] var json_definitions:blot_backend_native_assets::Definition[>..]=[];
fn allocate(self_:JsonOwner&,sample:blot_backend_native_assets::Definition,count:i64)->blot_backend_native_assets::Definition[:],Error {if count<0 || count>67108864 {return default<blot_backend_native_assets::Definition[:]>(),blot_error::Error.source_limit;}if count==0 {return default<blot_backend_native_assets::Definition[:]>(),blot_error::Error.none;}let values=json_definitions.alloc_slice(count);let error=self_.remember(JsonRun.definitions{values});if error!=blot_error::Error.none {json_definitions.free_slice(values);return default<blot_backend_native_assets::Definition[:]>(),error;}return values,blot_error::Error.none;}
reusable[] var json_roots:TextSlice[>..]=[];
fn allocate(self_:JsonOwner&,sample:TextSlice,count:i64)->TextSlice[:],Error {if count<0 || count>67108864 {return default<TextSlice[:]>(),blot_error::Error.source_limit;}if count==0 {return default<TextSlice[:]>(),blot_error::Error.none;}let values=json_roots.alloc_slice(count);let error=self_.remember(JsonRun.roots{values});if error!=blot_error::Error.none {json_roots.free_slice(values);return default<TextSlice[:]>(),error;}return values,blot_error::Error.none;}
fn alloc<T>(self_:JsonOwner&,count:i64)->T[:],Error {return self_.allocate(default<T>(),count);}
fn deinit(self_:JsonOwner&) {var next=self_.head;self_.head=0;while next!=0 {let at=next-1;let link=json_links[at];next=link.next;match link.run {bytes payload=>{json_bytes.free_slice(payload.values);},aliases payload=>{json_aliases.free_slice(payload.values);},ranges payload=>{json_ranges.free_slice(payload.values);},definitions payload=>{json_definitions.free_slice(payload.values);},roots payload=>{json_roots.free_slice(payload.values);}}json_links.free(at);}}
fn deinit(self_:ParsedRequest&) {self_.owner.deinit();self_=ParsedRequest{..};}
struct InputReader {raw:json::Reader,depth:i64=0,failure:Error=blot_error::Error.none}
fn fail(self_:InputReader&,error:Error)->Error {if self_.failure==blot_error::Error.none {self_.failure=error;}return self_.failure;}
fn character(self_:InputReader&,want:u8)->Error {if self_.raw.peek()!=want {return self_.fail(blot_error::Error.invalid_request);}self_.raw.pos++;return blot_error::Error.none;}
fn readText(self_:InputReader&,owner:JsonOwner&)->const u8[:],Error {var decoded:u8[>..]=[];let bytes=self_.raw.read_string(decoded);if self_.raw.error.len!=0 || !utf8(bytes) {return default<const u8[:]>(),self_.fail(blot_error::Error.invalid_request);}let owned,error=blot_reuse_zig_project_server::alloc<u8>(owner,bytes.len);if error!=blot_error::Error.none {return default<const u8[:]>(),self_.fail(error);}for byte,index in bytes {owned[index]=byte;}return owned,blot_error::Error.none;}
fn readValue(self_:InputReader&,value:const u8[:]& ,owner:JsonOwner&)->Error {let bytes,error=self_.readText(owner);if error!=blot_error::Error.none {return error;}value=bytes;return blot_error::Error.none;}
fn readUnsigned(self_:InputReader&,maximum:u64)->u64,Error {
 let first=self_.raw.peek();var negative=false;if first=='-' {negative=true;self_.raw.pos++;}if self_.raw.pos==self_.raw.text.len {return 0,self_.fail(blot_error::Error.invalid_request);}var value:u64=0;var digits:i64=0;let leading=self_.raw.text[self_.raw.pos];
 while self_.raw.pos<self_.raw.text.len {let byte=self_.raw.text[self_.raw.pos];if byte<'0' || byte>'9' {break;}let digit=(byte-'0') as u64;if value>maximum/10 || (value==maximum/10 && digit>maximum%10) {return 0,self_.fail(blot_error::Error.invalid_request);}value=value*10+digit;digits++;self_.raw.pos++;}
 if digits==0 || (digits>1 && leading=='0') || (negative && value!=0) {return 0,self_.fail(blot_error::Error.invalid_request);}return value,blot_error::Error.none;
}
fn readValue(self_:InputReader&,value:u8&,owner:JsonOwner&)->Error {let number,error=self_.readUnsigned(255);if error!=blot_error::Error.none {return error;}value=number as u8;return blot_error::Error.none;}
fn readValue(self_:InputReader&,value:u32&,owner:JsonOwner&)->Error {let number,error=self_.readUnsigned(4294967295);if error!=blot_error::Error.none {return error;}value=number as u32;return blot_error::Error.none;}
fn readValue(self_:InputReader&,value:u64&,owner:JsonOwner&)->Error {let number,error=self_.readUnsigned(18446744073709551615);if error!=blot_error::Error.none {return error;}value=number;return blot_error::Error.none;}
fn readValue(self_:InputReader&,value:bool&,owner:JsonOwner&)->Error {value=self_.raw.read_bool();if self_.raw.error.len!=0 {return self_.fail(blot_error::Error.invalid_request);}return blot_error::Error.none;}
fn readValue<T>(self_:InputReader&,value:blot_support::Option<T>&,owner:JsonOwner&)->Error {if self_.raw.peek()=='n' {self_.raw.word("null");if self_.raw.error.len!=0 {return self_.fail(blot_error::Error.invalid_request);}value=blot_support::none<T>();return blot_error::Error.none;}var decoded=default<T>();let error=self_.readValue(decoded,owner);if error!=blot_error::Error.none {return error;}value=blot_support::some(decoded);return blot_error::Error.none;}
fn readEnum<T>(self_:InputReader&,value:T&,owner:JsonOwner&)->Error {let name,error=self_.readText(owner);if error!=blot_error::Error.none {return error;}const for <N,V> in variants<T> {if name==N {value=V;return blot_error::Error.none;}}return self_.fail(blot_error::Error.invalid_request);}
fn readValue(self_:InputReader&,value:RequestKind&,owner:JsonOwner&)->Error {return self_.readEnum(value,owner);}
fn readValue(self_:InputReader&,value:blot_compilation_tier::Tier&,owner:JsonOwner&)->Error {return self_.readEnum(value,owner);}
fn readValue(self_:InputReader&,value:blot_backend_native_assets::Kind&,owner:JsonOwner&)->Error {return self_.readEnum(value,owner);}
fn readValue<T>(self_:InputReader&,value:const T[:]& ,owner:JsonOwner&)->Error {
 if self_.depth>=64 {return self_.fail(blot_error::Error.invalid_request);}self_.depth++;let error=self_.character('[');if error!=blot_error::Error.none {self_.depth--;return error;}if self_.raw.peek()==']' {self_.raw.pos++;self_.depth--;value=default<const T[:]>();return blot_error::Error.none;}
 // Discover the vector length without allocating a recursive growing owner.
 var scan=self_.raw;var count:i64=0;loop {scan.skip();if scan.error.len!=0 || count==4096 {self_.depth--;return self_.fail(blot_error::Error.source_limit);}count++;let next=scan.peek();if next==',' {scan.pos++;continue;}if next!=']' {self_.depth--;return self_.fail(blot_error::Error.invalid_request);}break;}
 let values,error=blot_reuse_zig_project_server::alloc<T>(owner,count);if error!=blot_error::Error.none {self_.depth--;return self_.fail(error);}for &element,index in values {element=default<T>();let error=self_.readValue(element,owner);if error!=blot_error::Error.none {self_.depth--;return error;}if index+1<count {let error=self_.character(',');if error!=blot_error::Error.none {self_.depth--;return error;}}}let error=self_.character(']');self_.depth--;if error!=blot_error::Error.none {return error;}value=values;return blot_error::Error.none;
}
fn wireName<T>(sample:T,name:const u8[:])->const u8[:] {return name;}
fn wireName(sample:blot_backend_native_assets::Definition,name:const u8[:])->const u8[:] {if name=="ty" {return "type";}if name=="export_name" {return "export";}return name;}
fn required<T>(sample:T,name:const u8[:])->bool {return false;}
fn required(sample:Request,name:const u8[:])->bool {return name=="kind" || name=="id";}
fn required(sample:SourceRange,name:const u8[:])->bool {return name=="path" || name=="start" || name=="length";}
fn required(sample:blot_reuse_project::Alias,name:const u8[:])->bool {return name=="prefix" || name=="root";}
fn required(sample:blot_backend_native_assets::Definition,name:const u8[:])->bool {return name=="module" || name=="path" || name=="kind";}
fn readRecord<T>(self_:InputReader&,value:T&,owner:JsonOwner&)->Error {
 if self_.depth>=64 {return self_.fail(blot_error::Error.invalid_request);}self_.depth++;let error=self_.character('{');if error!=blot_error::Error.none {self_.depth--;return error;}var seen:dictionary<const u8[:],bool> =dictionary<const u8[:],bool>{};
 if self_.raw.peek()!='}' {loop {let name,error=self_.readText(owner);if error!=blot_error::Error.none {self_.depth--;return error;}if seen.contains(name) {self_.depth--;return self_.fail(blot_error::Error.duplicate_field);}seen.insert(name,true);let error=self_.character(':');if error!=blot_error::Error.none {self_.depth--;return error;}var matched=false;
   const for <N,A> in fields<T> {if name==wireName(value,N) {matched=true;let error=self_.readValue(value.A,owner);if error!=blot_error::Error.none {self_.depth--;return error;}}}if !matched {self_.depth--;return self_.fail(blot_error::Error.unknown_field);}let next=self_.raw.peek();if next==',' {self_.raw.pos++;continue;}if next!='}' {self_.depth--;return self_.fail(blot_error::Error.invalid_request);}break;
 }}let error=self_.character('}');self_.depth--;if error!=blot_error::Error.none {return error;}const for <N,A> in fields<T> {if required(value,N) && !seen.contains(wireName(value,N)) {return self_.fail(blot_error::Error.missing_field);}}return blot_error::Error.none;
}
fn parseRequest(bytes:const u8[:])->ParsedRequest,Error {var result=ParsedRequest{..};var reader=InputReader{raw:json::reader(bytes),..};let error=reader.readValue(result.value,result.owner);if error!=blot_error::Error.none {result.deinit();return ParsedRequest{..},error;}if !reader.raw.finish() {result.deinit();return ParsedRequest{..},blot_error::Error.invalid_request;}return result,blot_error::Error.none;}

fn readValue(self_:InputReader&,value:Request&,owner:JsonOwner&)->Error {return self_.readRecord(value,owner);}

fn readValue(self_:InputReader&,value:SourceRange&,owner:JsonOwner&)->Error {return self_.readRecord(value,owner);}

fn readValue(self_:InputReader&,value:blot_reuse_project::Alias&,owner:JsonOwner&)->Error {return self_.readRecord(value,owner);}

fn readValue(self_:InputReader&,value:blot_backend_native_assets::Definition&,owner:JsonOwner&)->Error {return self_.readRecord(value,owner);}

fn readValue(self_:InputReader&,value:blot_backend_native_assets::Options&,owner:JsonOwner&)->Error {return self_.readRecord(value,owner);}

fn readValue(self_:InputReader&,value:blot_backend_storage_plan::Budgets&,owner:JsonOwner&)->Error {return self_.readRecord(value,owner);}
