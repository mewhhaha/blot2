// Request metadata is parsed as Zig's std.json parses it into the request
// type: integers may be written as strings or in float notation, an enum by
// name or by tag number, and the failures carry std.json's error names. Every
// decoded string and vector is owned independently.
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
// The syntax of the whole document is checked before any field is typed, so
// a typed read sees only well-formed tokens.
struct Syntax {text:const u8[:],pos:i64=0}
fn space(self_:Syntax&) {while self_.pos<self_.text.len {let byte=self_.text[self_.pos];if byte!=' ' && byte!='\t' && byte!='\n' && byte!='\r' {break;}self_.pos++;}}
fn literal(self_:Syntax&,word:const u8[:])->Error {for byte,index in word {if self_.pos+index>=self_.text.len {return blot_error::Error.unexpected_end_of_input;}if self_.text[self_.pos+index]!=byte {return blot_error::Error.syntax_error;}}self_.pos+=word.len;return blot_error::Error.none;}
fn digits(self_:Syntax&)->i64 {var count:i64=0;while self_.pos<self_.text.len && self_.text[self_.pos]>='0' && self_.text[self_.pos]<='9' {self_.pos++;count++;}return count;}
fn number(self_:Syntax&)->Error {
 if self_.text[self_.pos]=='-' {self_.pos++;}if self_.pos>=self_.text.len {return blot_error::Error.unexpected_end_of_input;}
 if self_.text[self_.pos]=='0' {self_.pos++;}else if self_.digits()==0 {return blot_error::Error.syntax_error;}
 if self_.pos<self_.text.len && self_.text[self_.pos]=='.' {self_.pos++;if self_.pos>=self_.text.len {return blot_error::Error.unexpected_end_of_input;}if self_.digits()==0 {return blot_error::Error.syntax_error;}}
 if self_.pos<self_.text.len && (self_.text[self_.pos]=='e' || self_.text[self_.pos]=='E') {self_.pos++;if self_.pos<self_.text.len && (self_.text[self_.pos]=='+' || self_.text[self_.pos]=='-') {self_.pos++;}if self_.pos>=self_.text.len {return blot_error::Error.unexpected_end_of_input;}if self_.digits()==0 {return blot_error::Error.syntax_error;}}
 return blot_error::Error.none;
}
fn hex(byte:u8)->i64 {if byte>='0' && byte<='9' {return (byte-'0') as i64;}if byte>='a' && byte<='f' {return (byte-'a') as i64+10;}if byte>='A' && byte<='F' {return (byte-'A') as i64+10;}return -1;}
fn unit(self_:Syntax&)->i64,Error {if self_.pos+4>self_.text.len {return 0,blot_error::Error.unexpected_end_of_input;}var value:i64=0;for index in 4 {let digit=hex(self_.text[self_.pos+index]);if digit<0 {return 0,blot_error::Error.syntax_error;}value=value*16+digit;}self_.pos+=4;return value,blot_error::Error.none;}
// Escapes are checked here; `decode` below relies on that.
fn string(self_:Syntax&)->Error {
 self_.pos++;
 loop {
  if self_.pos>=self_.text.len {return blot_error::Error.unexpected_end_of_input;}let byte=self_.text[self_.pos];
  if byte=='"' {self_.pos++;return blot_error::Error.none;}if byte<0x20 {return blot_error::Error.syntax_error;}
  if byte=='\\' {
   self_.pos++;if self_.pos>=self_.text.len {return blot_error::Error.unexpected_end_of_input;}let escape=self_.text[self_.pos];self_.pos++;
   if escape=='u' {
    let first,error=self_.unit();if error!=blot_error::Error.none {return error;}
    if first>=0xdc00 && first<=0xdfff {return blot_error::Error.syntax_error;}
    if first>=0xd800 && first<=0xdbff {if self_.pos+2>self_.text.len {return blot_error::Error.unexpected_end_of_input;}if self_.text[self_.pos]!='\\' || self_.text[self_.pos+1]!='u' {return blot_error::Error.syntax_error;}self_.pos+=2;let second,error=self_.unit();if error!=blot_error::Error.none {return error;}if second<0xdc00 || second>0xdfff {return blot_error::Error.syntax_error;}}
   }else if escape!='"' && escape!='\\' && escape!='/' && escape!='b' && escape!='f' && escape!='n' && escape!='r' && escape!='t' {return blot_error::Error.syntax_error;}
   continue;
  }
  if byte<0x80 {self_.pos++;continue;}
  let width=blot_parse_lexer::utf8_width(byte);if width==0 {return blot_error::Error.syntax_error;}if width>self_.text.len-self_.pos {return blot_error::Error.unexpected_end_of_input;}let point,error=blot_parse_lexer::decode_point(self_.text[self_.pos..self_.pos+width]);if error!=blot_error::Error.none {return blot_error::Error.syntax_error;}self_.pos+=width;
 }
}
fn document(text:const u8[:])->Error {
 var self_=Syntax{text:text,..};var open:bool[>..<]=[];var want_value=true;
 loop {
  self_.space();if self_.pos>=text.len {if open.len==0 && !want_value {return blot_error::Error.none;}return blot_error::Error.unexpected_end_of_input;}let byte=text[self_.pos];
  if !want_value {
   if open.len==0 {return blot_error::Error.syntax_error;}
   if byte==',' {self_.pos++;self_.space();if open[open.len-1] {if self_.pos>=text.len {return blot_error::Error.unexpected_end_of_input;}if text[self_.pos]!='"' {return blot_error::Error.syntax_error;}let error=self_.string();if error!=blot_error::Error.none {return error;}self_.space();if self_.pos>=text.len {return blot_error::Error.unexpected_end_of_input;}if text[self_.pos]!=':' {return blot_error::Error.syntax_error;}self_.pos++;}want_value=true;continue;}
   if (byte=='}' && open[open.len-1]) || (byte==']' && !open[open.len-1]) {self_.pos++;open.pop();continue;}
   return blot_error::Error.syntax_error;
  }
  if byte=='{' {
   if open.len>=1024 {return blot_error::Error.syntax_error;}self_.pos++;open.push(true);self_.space();if self_.pos>=text.len {return blot_error::Error.unexpected_end_of_input;}
   if text[self_.pos]=='}' {self_.pos++;open.pop();want_value=false;continue;}if text[self_.pos]!='"' {return blot_error::Error.syntax_error;}let error=self_.string();if error!=blot_error::Error.none {return error;}self_.space();if self_.pos>=text.len {return blot_error::Error.unexpected_end_of_input;}if text[self_.pos]!=':' {return blot_error::Error.syntax_error;}self_.pos++;continue;
  }
  if byte=='[' {if open.len>=1024 {return blot_error::Error.syntax_error;}self_.pos++;open.push(false);self_.space();if self_.pos<text.len && text[self_.pos]==']' {self_.pos++;open.pop();want_value=false;}continue;}
  var error=blot_error::Error.syntax_error;
  if byte=='"' {error=self_.string();}else if byte=='t' {error=self_.literal("true");}else if byte=='f' {error=self_.literal("false");}else if byte=='n' {error=self_.literal("null");}else if byte=='-' || (byte>='0' && byte<='9') {error=self_.number();}
  if error!=blot_error::Error.none {return error;}want_value=false;
 }
}
struct InputReader {text:const u8[:],pos:i64=0,depth:i64=0,failure:Error=blot_error::Error.none}
fn fail(self_:InputReader&,error:Error)->Error {if self_.failure==blot_error::Error.none {self_.failure=error;}return self_.failure;}
// The next byte that is not white space, not consumed. The document is well
// formed, so a value or a closing bracket always follows.
fn peek(self_:InputReader&)->u8 {while self_.pos<self_.text.len {let byte=self_.text[self_.pos];if byte!=' ' && byte!='\t' && byte!='\n' && byte!='\r' {return byte;}self_.pos++;}return 0;}
fn character(self_:InputReader&,want:u8)->Error {if self_.peek()!=want {return self_.fail(blot_error::Error.unexpected_token);}self_.pos++;return blot_error::Error.none;}
fn encode(point:i64,out:u8[>..]&) {if point<0x80 {out.push(point as u8);}else if point<0x800 {out.push((0xc0|(point>>6)) as u8);out.push((0x80|(point&0x3f)) as u8);}else if point<0x10000 {out.push((0xe0|(point>>12)) as u8);out.push((0x80|((point>>6)&0x3f)) as u8);out.push((0x80|(point&0x3f)) as u8);}else {out.push((0xf0|(point>>18)) as u8);out.push((0x80|((point>>12)&0x3f)) as u8);out.push((0x80|((point>>6)&0x3f)) as u8);out.push((0x80|(point&0x3f)) as u8);}}
// The string token at the cursor, decoded.
fn decode(self_:InputReader&,out:u8[>..]&) {
 self_.pos++;
 loop {
  let byte=self_.text[self_.pos];self_.pos++;if byte=='"' {return;}if byte!='\\' {out.push(byte);continue;}
  let escape=self_.text[self_.pos];self_.pos++;
  if escape=='b' {out.push(8);}else if escape=='f' {out.push(12);}else if escape=='n' {out.push('\n');}else if escape=='r' {out.push('\r');}else if escape=='t' {out.push('\t');}
  else if escape=='u' {var point:i64=0;for index in 4 {point=point*16+hex(self_.text[self_.pos+index]);}self_.pos+=4;if point>=0xd800 && point<=0xdbff {var low:i64=0;for index in 4 {low=low*16+hex(self_.text[self_.pos+2+index]);}self_.pos+=6;point=0x10000+((point-0xd800)<<10)+(low-0xdc00);}encode(point,out);}
  else {out.push(escape);}
 }
}
fn readText(self_:InputReader&,owner:JsonOwner&)->const u8[:],Error {
 if self_.peek()=='[' {let values,error=self_.readSlice(default<u8>(),owner);return values,error;}if self_.peek()!='"' {return default<const u8[:]>(),self_.fail(blot_error::Error.unexpected_token);}
 var decoded:u8[>..]=[];self_.decode(decoded);let owned,error=blot_reuse_zig_project_server::alloc<u8>(owner,decoded.len);if error!=blot_error::Error.none {return default<const u8[:]>(),self_.fail(error);}for byte,index in decoded {owned[index]=byte;}return owned,blot_error::Error.none;
}
fn readValue(self_:InputReader&,sample:const u8[:],owner:JsonOwner&)->const u8[:],Error {return self_.readText(owner);}
// A number token as written, or a string token decoded: the two forms
// std.json takes for an integer or an enum.
fn scalar(self_:InputReader&,out:u8[>..]&)->Error {
 let first=self_.peek();if first=='"' {self_.decode(out);return blot_error::Error.none;}if first!='-' && (first<'0' || first>'9') {return self_.fail(blot_error::Error.unexpected_token);}
 while self_.pos<self_.text.len {let byte=self_.text[self_.pos];if (byte<'0' || byte>'9') && byte!='-' && byte!='+' && byte!='.' && byte!='e' && byte!='E' {break;}out.push(byte);self_.pos++;}return blot_error::Error.none;
}
fn integerFormatted(text:const u8[:])->bool {if text=="-0" {return false;}for byte in text {if byte=='.' || byte=='e' || byte=='E' {return false;}}return true;}
// std.fmt.parseInt in base 10: a sign, then digits with underscores between.
fn parseInteger(text:const u8[:],maximum:u64)->u64,Error {
 var at:i64=0;var negative=false;if text.len!=0 && (text[0]=='+' || text[0]=='-') {negative=text[0]=='-';at=1;}if at==text.len || text[at]=='_' || text[text.len-1]=='_' {return 0,blot_error::Error.invalid_character;}
 var value:u64=0;while at<text.len {let byte=text[at];at++;if byte=='_' {continue;}if byte<'0' || byte>'9' {return 0,blot_error::Error.invalid_character;}let digit=(byte-'0') as u64;if negative {if digit!=0 {return 0,blot_error::Error.overflow;}continue;}if value>maximum/10 || (value==maximum/10 && digit>maximum%10) {return 0,blot_error::Error.overflow;}value=value*10+digit;}return value,blot_error::Error.none;
}
// A decimal float that names a whole number, as sliceToInt coerces it.
fn parseWhole(text:const u8[:],maximum:u64)->u64,Error {
 var at:i64=0;var negative=false;if text.len!=0 && (text[0]=='+' || text[0]=='-') {negative=text[0]=='-';at=1;}
 var mantissa:u8[>..]=[];var fraction:i64=0;var seen=false;while at<text.len && text[at]>='0' && text[at]<='9' {mantissa.push(text[at]-'0');at++;seen=true;}
 if at<text.len && text[at]=='.' {at++;while at<text.len && text[at]>='0' && text[at]<='9' {mantissa.push(text[at]-'0');at++;fraction++;seen=true;}}if !seen {return 0,blot_error::Error.invalid_character;}
 var exponent:i64=0;if at<text.len && (text[at]=='e' || text[at]=='E') {at++;var down=false;if at<text.len && (text[at]=='+' || text[at]=='-') {down=text[at]=='-';at++;}if at==text.len {return 0,blot_error::Error.invalid_character;}while at<text.len {let byte=text[at];at++;if byte<'0' || byte>'9' {return 0,blot_error::Error.invalid_character;}if exponent<100000 {exponent=exponent*10+(byte-'0') as i64;}}if down {exponent=-exponent;}}
 if at!=text.len {return 0,blot_error::Error.invalid_character;}
 var shift=exponent-fraction;var kept=mantissa.len;while shift<0 && kept>0 {if mantissa[kept-1]!=0 {return 0,blot_error::Error.invalid_number;}kept--;shift++;}
 var value:u64=0;var zero=true;for digit in mantissa[..kept] {if digit!=0 {zero=false;}if value>maximum/10 || (value==maximum/10 && digit as u64>maximum%10) {return 0,blot_error::Error.overflow;}value=value*10+digit as u64;}
 if zero {return 0,blot_error::Error.none;}if negative {return 0,blot_error::Error.overflow;}while shift>0 {if value>maximum/10 {return 0,blot_error::Error.overflow;}value*=10;shift--;}return value,blot_error::Error.none;
}
fn readUnsigned(self_:InputReader&,maximum:u64)->u64,Error {
 var text:u8[>..]=[];let error=self_.scalar(text);if error!=blot_error::Error.none {return 0,error;}
 if integerFormatted(text[..]) {let value,error=parseInteger(text[..],maximum);if error!=blot_error::Error.none {return 0,self_.fail(error);}return value,blot_error::Error.none;}
 let value,error=parseWhole(text[..],maximum);if error!=blot_error::Error.none {return 0,self_.fail(error);}return value,blot_error::Error.none;
}
fn readValue(self_:InputReader&,sample:u8,owner:JsonOwner&)->u8,Error {let number,error=self_.readUnsigned(255);if error!=blot_error::Error.none {return 0,error;}return number as u8,blot_error::Error.none;}
fn readValue(self_:InputReader&,sample:u32,owner:JsonOwner&)->u32,Error {let number,error=self_.readUnsigned(4294967295);if error!=blot_error::Error.none {return 0,error;}return number as u32,blot_error::Error.none;}
fn readValue(self_:InputReader&,sample:u64,owner:JsonOwner&)->u64,Error {return self_.readUnsigned(18446744073709551615);}
fn readValue(self_:InputReader&,sample:bool,owner:JsonOwner&)->bool,Error {let first=self_.peek();if first=='t' {self_.pos+=4;return true,blot_error::Error.none;}if first=='f' {self_.pos+=5;return false,blot_error::Error.none;}return false,self_.fail(blot_error::Error.unexpected_token);}
fn readValue<T>(self_:InputReader&,sample:blot_support::Option<T>,owner:JsonOwner&)->blot_support::Option<T>,Error {
 if self_.peek()=='n' {self_.pos+=4;return blot_support::none<T>(),blot_error::Error.none;}
 let decoded,error=self_.readValue(default<T>(),owner);if error!=blot_error::Error.none {return blot_support::none<T>(),error;}return blot_support::some<T>(decoded),blot_error::Error.none;
}
// By name, or by the tag's number.
fn readEnum<T>(self_:InputReader&,sample:T,owner:JsonOwner&)->T,Error {
 var name:u8[>..]=[];let error=self_.scalar(name);if error!=blot_error::Error.none {return default<T>(),error;}const for <N,V> in variants<T> {if name[..]==N {return V,blot_error::Error.none;}}
 if !integerFormatted(name[..]) {return default<T>(),self_.fail(blot_error::Error.invalid_enum_tag);}let tag,error=parseInteger(name[..],255);if error!=blot_error::Error.none {return default<T>(),self_.fail(blot_error::Error.invalid_enum_tag);}
 var index:u64=0;const for <N,V> in variants<T> {if tag==index {return V,blot_error::Error.none;}index++;}return default<T>(),self_.fail(blot_error::Error.invalid_enum_tag);
}
fn readValue(self_:InputReader&,sample:RequestKind,owner:JsonOwner&)->RequestKind,Error {return self_.readEnum(sample,owner);}
fn readValue(self_:InputReader&,sample:blot_backend_native_assets::Kind,owner:JsonOwner&)->blot_backend_native_assets::Kind,Error {return self_.readEnum(sample,owner);}
// The cursor after the value at `at`.
fn after(text:const u8[:],at:i64)->i64 {
 var pos=at;var depth:i64=0;
 loop {
  let byte=text[pos];
  if byte=='"' {pos++;while text[pos]!='"' {if text[pos]=='\\' {pos++;}pos++;}pos++;}
  else if byte=='{' || byte=='[' {depth++;pos++;continue;}
  else if byte=='}' || byte==']' {depth--;pos++;}
  else if byte==',' || byte==':' || byte==' ' || byte=='\t' || byte=='\n' || byte=='\r' {pos++;continue;}
  else {while pos<text.len && text[pos]!=',' && text[pos]!='}' && text[pos]!=']' && text[pos]!=' ' && text[pos]!='\t' && text[pos]!='\n' && text[pos]!='\r' {pos++;}}
  if depth==0 {return pos;}
 }
}
fn readSlice<T>(self_:InputReader&,sample:T,owner:JsonOwner&)->const T[:],Error {
 if self_.depth>=64 {return default<const T[:]>(),self_.fail(blot_error::Error.syntax_error);}if self_.peek()!='[' {return default<const T[:]>(),self_.fail(blot_error::Error.unexpected_token);}self_.pos++;if self_.peek()==']' {self_.pos++;return default<const T[:]>(),blot_error::Error.none;}
 // Discover the vector length without allocating a recursive growing owner.
 var scan=self_.pos;var count:i64=0;loop {while self_.text[scan]==' ' || self_.text[scan]=='\t' || self_.text[scan]=='\n' || self_.text[scan]=='\r' {scan++;}scan=after(self_.text,scan);count++;while self_.text[scan]==' ' || self_.text[scan]=='\t' || self_.text[scan]=='\n' || self_.text[scan]=='\r' {scan++;}if self_.text[scan]==',' {scan++;continue;}break;}
 if count>4096 {return default<const T[:]>(),self_.fail(blot_error::Error.source_limit);}
 let values,error=blot_reuse_zig_project_server::alloc<T>(owner,count);if error!=blot_error::Error.none {return default<const T[:]>(),self_.fail(error);}for index in values.len {values[index]=default<T>();}
 self_.depth++;for index in values.len {let element,error=self_.readValue(default<T>(),owner);if error!=blot_error::Error.none {self_.depth--;return default<const T[:]>(),error;}values[index]=element;if index+1<count {let error=self_.character(',');if error!=blot_error::Error.none {self_.depth--;return default<const T[:]>(),error;}}}
 self_.depth--;let error=self_.character(']');if error!=blot_error::Error.none {return default<const T[:]>(),error;}return values,blot_error::Error.none;
}
fn readValue<T>(self_:InputReader&,sample:const T[:],owner:JsonOwner&)->const T[:],Error {return self_.readSlice(default<T>(),owner);}
fn wireName<T>(sample:T,name:const u8[:])->const u8[:] {return name;}
fn wireName(sample:blot_backend_native_assets::Definition,name:const u8[:])->const u8[:] {if name=="ty" {return "type";}if name=="export_name" {return "export";}return name;}
fn required<T>(sample:T,name:const u8[:])->bool {return false;}
fn required(sample:Request,name:const u8[:])->bool {return name=="kind" || name=="id";}
fn required(sample:SourceRange,name:const u8[:])->bool {return name=="path" || name=="start" || name=="length";}
fn required(sample:blot_reuse_project::Alias,name:const u8[:])->bool {return name=="prefix" || name=="root";}
fn required(sample:blot_backend_native_assets::Definition,name:const u8[:])->bool {return name=="module" || name=="path" || name=="kind";}
fn readRecord<T>(self_:InputReader&,sample:T,owner:JsonOwner&)->T,Error {
 var value=default<T>();
 if self_.depth>=64 {return value,self_.fail(blot_error::Error.syntax_error);}if self_.peek()!='{' {return value,self_.fail(blot_error::Error.unexpected_token);}self_.pos++;self_.depth++;var seen:dictionary<const u8[:],bool> =dictionary<const u8[:],bool>{};
 if self_.peek()!='}' {loop {if self_.peek()!='"' {self_.depth--;return value,self_.fail(blot_error::Error.unexpected_token);}var key:u8[>..]=[];self_.decode(key);let name,error=blot_reuse_zig_project_server::alloc<u8>(owner,key.len);if error!=blot_error::Error.none {self_.depth--;return value,self_.fail(error);}for byte,index in key {name[index]=byte;}
   let error=self_.character(':');if error!=blot_error::Error.none {self_.depth--;return value,error;}var matched=false;
   const for <N,A> in fields<T> {if name==wireName(value,N) {matched=true;if seen.contains(name) {self_.depth--;return value,self_.fail(blot_error::Error.duplicate_field);}let decoded,error=self_.readValue(value.A,owner);if error!=blot_error::Error.none {self_.depth--;return value,error;}value.A=decoded;}}if !matched {self_.depth--;return value,self_.fail(blot_error::Error.unknown_field);}seen.insert(name,true);let next=self_.peek();if next==',' {self_.pos++;continue;}break;
 }}self_.pos++;self_.depth--;const for <N,A> in fields<T> {if required(value,N) && !seen.contains(wireName(value,N)) {return value,self_.fail(blot_error::Error.missing_field);}}return value,blot_error::Error.none;
}
fn parseRequest(bytes:const u8[:])->ParsedRequest,Error {let error=document(bytes);if error!=blot_error::Error.none {return ParsedRequest{..},error;}var result=ParsedRequest{..};var reader=InputReader{text:bytes,..};let value,error=reader.readValue(default<Request>(),result.owner);if error!=blot_error::Error.none {result.deinit();return ParsedRequest{..},error;}result.value=value;return result,blot_error::Error.none;}

fn readValue(self_:InputReader&,sample:Request,owner:JsonOwner&)->Request,Error {return self_.readRecord(sample,owner);}

fn readValue(self_:InputReader&,sample:SourceRange,owner:JsonOwner&)->SourceRange,Error {return self_.readRecord(sample,owner);}

fn readValue(self_:InputReader&,sample:blot_reuse_project::Alias,owner:JsonOwner&)->blot_reuse_project::Alias,Error {return self_.readRecord(sample,owner);}

fn readValue(self_:InputReader&,sample:blot_backend_native_assets::Definition,owner:JsonOwner&)->blot_backend_native_assets::Definition,Error {return self_.readRecord(sample,owner);}

fn readValue(self_:InputReader&,sample:blot_backend_native_assets::Options,owner:JsonOwner&)->blot_backend_native_assets::Options,Error {return self_.readRecord(sample,owner);}

fn readValue(self_:InputReader&,sample:StorageBudgets,owner:JsonOwner&)->StorageBudgets,Error {return self_.readRecord(sample,owner);}
