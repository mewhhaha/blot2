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
fn remember(self:JsonOwner&,run:JsonRun)->Error {if json_links.len>=0xffffffff {return Error.out_of_memory;}let at=json_links.alloc_index(JsonLink{run,self.head});self.head=(at+1) as u32;return Error.none;}
reusable[] var json_bytes:u8[>..]=[];
fn allocate(self:JsonOwner&,sample:u8,count:i64)->u8[:],Error {if count<0 || count>67108864 {return [],Error.source_limit;}if count==0 {return [],Error.none;}let values=json_bytes.alloc_slice(count);let error=self.remember(JsonRun.bytes{values});if error!=Error.none {json_bytes.free_slice(values);return [],error;}return values,Error.none;}
reusable[] var json_aliases:blot_reuse_project::Alias[>..]=[];
fn allocate(self:JsonOwner&,sample:blot_reuse_project::Alias,count:i64)->blot_reuse_project::Alias[:],Error {if count<0 || count>67108864 {return [],Error.source_limit;}if count==0 {return [],Error.none;}let values=json_aliases.alloc_slice(count);let error=self.remember(JsonRun.aliases{values});if error!=Error.none {json_aliases.free_slice(values);return [],error;}return values,Error.none;}
reusable[] var json_ranges:SourceRange[>..]=[];
fn allocate(self:JsonOwner&,sample:SourceRange,count:i64)->SourceRange[:],Error {if count<0 || count>67108864 {return [],Error.source_limit;}if count==0 {return [],Error.none;}let values=json_ranges.alloc_slice(count);let error=self.remember(JsonRun.ranges{values});if error!=Error.none {json_ranges.free_slice(values);return [],error;}return values,Error.none;}
reusable[] var json_definitions:blot_backend_native_assets::Definition[>..]=[];
fn allocate(self:JsonOwner&,sample:blot_backend_native_assets::Definition,count:i64)->blot_backend_native_assets::Definition[:],Error {if count<0 || count>67108864 {return [],Error.source_limit;}if count==0 {return [],Error.none;}let values=json_definitions.alloc_slice(count);let error=self.remember(JsonRun.definitions{values});if error!=Error.none {json_definitions.free_slice(values);return [],error;}return values,Error.none;}
reusable[] var json_roots:TextSlice[>..]=[];
fn allocate(self:JsonOwner&,sample:TextSlice,count:i64)->TextSlice[:],Error {if count<0 || count>67108864 {return [],Error.source_limit;}if count==0 {return [],Error.none;}let values=json_roots.alloc_slice(count);let error=self.remember(JsonRun.roots{values});if error!=Error.none {json_roots.free_slice(values);return [],error;}return values,Error.none;}
fn alloc<T>(self:JsonOwner&,count:i64)->T[:],Error {return self.allocate(default<T>(),count);}
fn deinit(self:JsonOwner&) {var next=self.head;self.head=0;while next!=0 {let at=next-1;let link=json_links[at];next=link.next;match link.run {JsonRun.bytes payload=>{json_bytes.free_slice(payload.values);}JsonRun.aliases payload=>{json_aliases.free_slice(payload.values);}JsonRun.ranges payload=>{json_ranges.free_slice(payload.values);}JsonRun.definitions payload=>{json_definitions.free_slice(payload.values);}JsonRun.roots payload=>{json_roots.free_slice(payload.values);}}json_links.free(at);}}
fn deinit(self:ParsedRequest&) {self.owner.deinit();self=ParsedRequest{..};}
struct InputReader {raw:json::Reader,depth:i64=0,failure:Error=Error.none}
fn fail(self:InputReader&,error:Error)->Error {if self.failure==Error.none {self.failure=error;}return self.failure;}
fn character(self:InputReader&,want:u8)->Error {if self.raw.peek()!=want {return self.fail(Error.invalid_request);}self.raw.pos++;return Error.none;}
fn readText(self:InputReader&,owner:JsonOwner&)->const u8[:],Error {var decoded:u8[>..]=[];let bytes=self.raw.read_string(decoded);if self.raw.error.len!=0 || !utf8(bytes) {return [],self.fail(Error.invalid_request);}let owned,error=owner.alloc<u8>(bytes.len);if error!=Error.none {return [],self.fail(error);}for byte,index in bytes {owned[index]=byte;}return owned,Error.none;}
fn readValue(self:InputReader&,value:const u8[:]& ,owner:JsonOwner&)->Error {let bytes,error=self.readText(owner);if error!=Error.none {return error;}value=bytes;return Error.none;}
fn readUnsigned(self:InputReader&,maximum:u64)->u64,Error {
 let first=self.raw.peek();var negative=false;if first=='-' {negative=true;self.raw.pos++;}if self.raw.pos==self.raw.text.len {return 0,self.fail(Error.invalid_request);}var value:u64=0;var digits:i64=0;let leading=self.raw.text[self.raw.pos];
 while self.raw.pos<self.raw.text.len {let byte=self.raw.text[self.raw.pos];if byte<'0' || byte>'9' {break;}let digit=(byte-'0') as u64;if value>maximum/10 || (value==maximum/10 && digit>maximum%10) {return 0,self.fail(Error.invalid_request);}value=value*10+digit;digits++;self.raw.pos++;}
 if digits==0 || (digits>1 && leading=='0') || (negative && value!=0) {return 0,self.fail(Error.invalid_request);}return value,Error.none;
}
fn readValue(self:InputReader&,value:u8&,owner:JsonOwner&)->Error {let number,error=self.readUnsigned(255);if error!=Error.none {return error;}value=number as u8;return Error.none;}
fn readValue(self:InputReader&,value:u32&,owner:JsonOwner&)->Error {let number,error=self.readUnsigned(4294967295);if error!=Error.none {return error;}value=number as u32;return Error.none;}
fn readValue(self:InputReader&,value:u64&,owner:JsonOwner&)->Error {let number,error=self.readUnsigned(18446744073709551615);if error!=Error.none {return error;}value=number;return Error.none;}
fn readValue(self:InputReader&,value:bool&,owner:JsonOwner&)->Error {value=self.raw.read_bool();if self.raw.error.len!=0 {return self.fail(Error.invalid_request);}return Error.none;}
fn readValue<T>(self:InputReader&,value:blot_support::Option<T>&,owner:JsonOwner&)->Error {if self.raw.peek()=='n' {self.raw.word("null");if self.raw.error.len!=0 {return self.fail(Error.invalid_request);}value=blot_support::none<T>();return Error.none;}var decoded=default<T>();let error=self.readValue(decoded,owner);if error!=Error.none {return error;}value=blot_support::some(decoded);return Error.none;}
fn readEnum<T>(self:InputReader&,value:T&,owner:JsonOwner&)->Error {let name,error=self.readText(owner);if error!=Error.none {return error;}const for <N,V> in variants<T> {if name==N {value=V;return Error.none;}}return self.fail(Error.invalid_request);}
fn readValue(self:InputReader&,value:RequestKind&,owner:JsonOwner&)->Error {return self.readEnum(value,owner);}
fn readValue(self:InputReader&,value:blot_compilation_tier::Tier&,owner:JsonOwner&)->Error {return self.readEnum(value,owner);}
fn readValue(self:InputReader&,value:blot_backend_native_assets::Kind&,owner:JsonOwner&)->Error {return self.readEnum(value,owner);}
fn readValue<T>(self:InputReader&,value:const T[:]& ,owner:JsonOwner&)->Error {
 if self.depth>=64 {return self.fail(Error.invalid_request);}self.depth++;let error=self.character('[');if error!=Error.none {self.depth--;return error;}if self.raw.peek()==']' {self.raw.pos++;self.depth--;value=[];return Error.none;}
 // Discover the vector length without allocating a recursive growing owner.
 var scan=self.raw;var count:i64=0;loop {scan.skip();if scan.error.len!=0 || count==4096 {self.depth--;return self.fail(Error.source_limit);}count++;let next=scan.peek();if next==',' {scan.pos++;continue;}if next!=']' {self.depth--;return self.fail(Error.invalid_request);}break;}
 let values,error=owner.alloc<T>(count);if error!=Error.none {self.depth--;return self.fail(error);}for &element,index in values {element=default<T>();let error=self.readValue(element,owner);if error!=Error.none {self.depth--;return error;}if index+1<count {let error=self.character(',');if error!=Error.none {self.depth--;return error;}}}let error=self.character(']');self.depth--;if error!=Error.none {return error;}value=values;return Error.none;
}
fn wireName<T>(sample:T,name:const u8[:])->const u8[:] {return name;}
fn wireName(sample:blot_backend_native_assets::Definition,name:const u8[:])->const u8[:] {if name=="ty" {return "type";}if name=="export_name" {return "export";}return name;}
fn required<T>(sample:T,name:const u8[:])->bool {return false;}
fn required(sample:Request,name:const u8[:])->bool {return name=="kind" || name=="id";}
fn required(sample:SourceRange,name:const u8[:])->bool {return name=="path" || name=="start" || name=="length";}
fn required(sample:blot_reuse_project::Alias,name:const u8[:])->bool {return name=="prefix" || name=="root";}
fn required(sample:blot_backend_native_assets::Definition,name:const u8[:])->bool {return name=="module" || name=="path" || name=="kind";}
fn readValue<T>(self:InputReader&,value:T&,owner:JsonOwner&)->Error {
 if self.depth>=64 {return self.fail(Error.invalid_request);}self.depth++;let error=self.character('{');if error!=Error.none {self.depth--;return error;}var seen:dictionary<const u8[:],bool>=dictionary<const u8[:],bool>{};
 if self.raw.peek()!='}' {loop {let name,error=self.readText(owner);if error!=Error.none {self.depth--;return error;}if seen.contains(name) {self.depth--;return self.fail(Error.duplicate_field);}seen.insert(name,true);let error=self.character(':');if error!=Error.none {self.depth--;return error;}var matched=false;
   const for <N,A> in fields<T> {if name==wireName(value,N) {matched=true;let error=self.readValue(value.A,owner);if error!=Error.none {self.depth--;return error;}}}if !matched {self.depth--;return self.fail(Error.unknown_field);}let next=self.raw.peek();if next==',' {self.raw.pos++;continue;}if next!='}' {self.depth--;return self.fail(Error.invalid_request);}break;
 }}let error=self.character('}');self.depth--;if error!=Error.none {return error;}const for <N,A> in fields<T> {if required(value,N) && !seen.contains(wireName(value,N)) {return self.fail(Error.missing_field);}}return Error.none;
}
fn parseRequest(bytes:const u8[:])->ParsedRequest,Error {var result=ParsedRequest{..};var reader=InputReader{raw:json::reader(bytes),..};let error=reader.readValue(result.value,result.owner);if error!=Error.none {result.deinit();return ParsedRequest{..},error;}if !reader.raw.finish() {result.deinit();return ParsedRequest{..},Error.invalid_request;}return result,Error.none;}
