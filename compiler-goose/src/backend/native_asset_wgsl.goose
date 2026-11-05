// Bounded WGSL syntax and constant reflection; shader bodies are never retained.
namespace blot_backend_native_asset_wgsl;
import std;
import math;
import dictionary;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;
import .optimizer_buffers;
import .native_asset_numbers;
import .native_asset_readers;
type Error=blot_error::Error;
type Text=blot_backend_optimizer_buffers::Bytes;
struct Issue {start:u32=0,end:u32=0,code:const u8[:],message:const u8[:]}
enum Result {source{bytes:u8[:]},issue{value:Issue}}
let limit:i64=16777216;
struct Token {text:const u8[:],start:u32,end:u32,number:bool=false}
enum Kind {unknown,x32,f32_value,u32_value,i32_value,boolean,f16_value}
struct Value {kind:Kind=Kind.unknown,n:f64=0.0,elements:const Value[:]=[],literal:bool=true}
struct Binding {name:const u8[:],value:Value}
struct Field {name:const u8[:],type_name:const u8[:],token:Token}
struct ValueRun {values:Value[:]}
struct Operator {text:const u8[:]=[],precedence:u8=0,count:i64=1}
reusable[] var output_pool:u8[>..]=[];
reusable[] var element_pool:Value[>..]=[];
fn copyOutput(bytes:const u8[:])->u8[:] {let result=output_pool.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn freeOutput(bytes:const u8[:]) {if bytes.len!=0 {let first:const u8&=bytes[0];let start=output_pool.index_of(first);output_pool.free_slice(output_pool[start..start+bytes.len]);}}
fn deinit(result:Result&) {match result {Result.source value=>{freeOutput(value.bytes);},Result.issue value=>{freeOutput(value.value.message);},}result=Result.source{bytes:[]};}
struct Tokens {storage:Token[:]=[],items:Token[:]=[],len:i64=0}
reusable[] var pool_Tokens:Token[>..]=[];
fn push(self:Tokens&,value:Token)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Tokens);self.len=self.items.len;return error;}
fn deinit(self:Tokens&) {blot_support_pooled_buffer::deinit(self,pool_Tokens);self.len=0;}
struct Bindings {storage:Binding[:]=[],items:Binding[:]=[],len:i64=0}
reusable[] var pool_Bindings:Binding[>..]=[];
fn push(self:Bindings&,value:Binding)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Bindings);self.len=self.items.len;return error;}
fn deinit(self:Bindings&) {blot_support_pooled_buffer::deinit(self,pool_Bindings);self.len=0;}
struct Fields {storage:Field[:]=[],items:Field[:]=[],len:i64=0}
reusable[] var pool_Fields:Field[>..]=[];
fn push(self:Fields&,value:Field)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Fields);self.len=self.items.len;return error;}
fn deinit(self:Fields&) {blot_support_pooled_buffer::deinit(self,pool_Fields);self.len=0;}
struct Values {storage:Value[:]=[],items:Value[:]=[],len:i64=0}
reusable[] var pool_Values:Value[>..]=[];
fn push(self:Values&,value:Value)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Values);self.len=self.items.len;return error;}
fn deinit(self:Values&) {blot_support_pooled_buffer::deinit(self,pool_Values);self.len=0;}
struct Runs {storage:ValueRun[:]=[],items:ValueRun[:]=[],len:i64=0}
reusable[] var pool_Runs:ValueRun[>..]=[];
fn push(self:Runs&,value:ValueRun)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Runs);self.len=self.items.len;return error;}
fn deinit(self:Runs&) {blot_support_pooled_buffer::deinit(self,pool_Runs);self.len=0;}
struct Index {table:blot_support_pooled_map::Map<const u8[:],u32>=blot_support_pooled_map::Map<const u8[:],u32>{..}}
reusable[] var slots_Index:dictionary_slot<const u8[:],u32>[>..]=[];
fn get(self:const Index&,key:const u8[:])->u32? {return blot_support_pooled_map::get(self.table,key);}
fn insert(self:Index&,key:const u8[:],value:u32) {blot_support_pooled_map::insert(self.table,key,value,slots_Index);}
fn deinit(self:Index&) {blot_support_pooled_map::deinit(self.table,slots_Index);}
struct Aliases {table:blot_support_pooled_map::Map<const u8[:],const u8[:]>=blot_support_pooled_map::Map<const u8[:],const u8[:]>{..}}
reusable[] var slots_Aliases:dictionary_slot<const u8[:],const u8[:]>[>..]=[];
fn get(self:const Aliases&,key:const u8[:])->const u8[:]? {return blot_support_pooled_map::get(self.table,key);}
fn insert(self:Aliases&,key:const u8[:],value:const u8[:]) {blot_support_pooled_map::insert(self.table,key,value,slots_Aliases);}
fn deinit(self:Aliases&) {blot_support_pooled_map::deinit(self.table,slots_Aliases);}
struct Reader {input:const u8[:],tokens:Tokens=Tokens{..},at:i64=0,visits:i64=0,bindings:Bindings=Bindings{..},binding_index:Index=Index{..},aliases:Aliases=Aliases{..},fields:Fields=Fields{..},parameters:bool=false,constant_mode:bool=false,call_depth:i64=0,header:Text=Text{..},body:Text=Text{..},issue:blot_support::Option<Issue>=blot_support::Option<Issue>{..},runs:Runs=Runs{..},failure:Error=Error.none}
fn deinit(self:Reader&) {for run in self.runs.items {if run.values.len!=0 {element_pool.free_slice(run.values);}}self.runs.deinit();self.tokens.deinit();self.bindings.deinit();self.binding_index.deinit();self.aliases.deinit();self.fields.deinit();self.header.deinit();self.body.deinit();}
fn record(self:Reader&,error:Error) {if self.failure==Error.none && error!=Error.none {self.failure=error;}}
fn fail(self:Reader&,token:Token,code:const u8[:],message:const u8[:]) {if self.failure!=Error.none {return;}self.issue=blot_support::some(Issue{start:token.start,end:token.end,code:code,message:message});self.failure=Error.invalid_asset;}
fn peek(self:const Reader&)->Token {if self.at>=self.tokens.len {return Token{text:[],start:self.input.len as u32,end:self.input.len as u32,..};}return self.tokens.items[self.at];}
fn syntax(self:Reader&) {self.fail(self.peek(),"asset_wgsl","Malformed WGSL asset");}
fn budget(self:Reader&,depth:i64)->bool {if self.failure!=Error.none {return false;}self.visits+=1;if depth>128 || self.visits>1000000 {self.fail(self.peek(),"asset_limit","WGSL asset exceeds the structural budget");return false;}return true;}
fn is(self:const Reader&,text:const u8[:])->bool {return self.peek().text==text;}
fn take(self:Reader&,text:const u8[:])->bool {if self.failure!=Error.none || !self.is(text) {return false;}self.at+=1;return true;}
fn expect(self:Reader&,text:const u8[:]) {if self.failure==Error.none && !self.take(text) {self.syntax();}}
fn name(self:Reader&)->Token {let token=self.peek();if self.failure!=Error.none {return token;}if token.text.len==0 || !identifierStart(token.text[0]) {self.syntax();return token;}self.at+=1;return token;}
fn put(self:Reader&,out:Text&,text:const u8[:]) {if self.failure!=Error.none {return;}if text.len>limit || out.len>limit-text.len {self.fail(self.peek(),"asset_limit","Generated asset module exceeds 16 MiB");return;}self.record(out.append(text));}
fn elements(self:Reader&,count:i64)->Value[:] {if self.failure!=Error.none || count==0 {return [];}let result=element_pool.alloc_slice(count);let error=self.runs.push(ValueRun{values:result});if error!=Error.none {element_pool.free_slice(result);self.record(error);return [];}for &value in result {value=Value{..};}return result;}
fn ownElements(self:Reader&,values:const Value[:])->const Value[:] {let result=self.elements(values.len);if self.failure!=Error.none {return [];}for value,index in values {result[index]=value;}return result;}
fn digit(byte:u8)->bool {return byte>='0' && byte<='9';}
fn identifierStart(byte:u8)->bool {return (byte>='a' && byte<='z') || (byte>='A' && byte<='Z') || byte=='_';}
fn identifierContinue(byte:u8)->bool {return identifierStart(byte) || digit(byte);}
fn contains(text:const u8[:],byte:u8)->bool {for item in text {if item==byte {return true;}}return false;}
fn starts(text:const u8[:],prefix:const u8[:])->bool {return text.len>=prefix.len && text[..prefix.len]==prefix;}
fn ends(text:const u8[:],suffix:const u8[:])->bool {return text.len>=suffix.len && text[text.len-suffix.len..]==suffix;}
fn lex(self:Reader&) {if self.input.len>limit {self.fail(Token{text:[],start:0,end:0,..},"asset_limit","WGSL asset exceeds 16 MiB");return;}var unicode:i64=0;while unicode<self.input.len {let point,length,valid=blot_backend_native_asset_readers::decodePoint(self.input,unicode);if !valid {self.fail(Token{text:[],start:0,end:self.input.len as u32,..},"asset_unicode","WGSL asset must be valid UTF-8");return;}unicode+=length;}var pos:i64=0;while pos<self.input.len && self.failure==Error.none {let byte=self.input[pos];if contains(" \t\r\n",byte) {pos+=1;continue;}if starts(self.input[pos..],"//") {while pos<self.input.len && self.input[pos]!='\n' {pos+=1;}continue;}if starts(self.input[pos..],"/*") {let start=pos;pos+=2;var nesting:i64=1;while pos<self.input.len && nesting!=0 {if starts(self.input[pos..],"/*") {nesting+=1;if nesting>128 {self.fail(Token{text:[],start:start as u32,end:(pos+2) as u32,..},"asset_limit","WGSL comment nesting exceeds 128");return;}pos+=2;}else if starts(self.input[pos..],"*/") {nesting-=1;pos+=2;}else {pos+=1;}}if nesting!=0 {self.fail(Token{text:[],start:start as u32,end:pos as u32,..},"asset_wgsl","Unterminated WGSL block comment");return;}continue;}let start=pos;var number=false;if identifierStart(byte) {pos+=1;while pos<self.input.len && identifierContinue(self.input[pos]) {pos+=1;}}else if digit(byte) || (byte=='.' && pos+1<self.input.len && digit(self.input[pos+1])) {number=true;pos+=1;while pos<self.input.len {let c=self.input[pos];if identifierContinue(c) || c=='.' {pos+=1;}else if (c=='+' || c=='-') && pos>start && contains("eEpP",self.input[pos-1]) {pos+=1;}else {break;}}}else {if !contains("@{}()[]<>,:;.=+-*/%!~&|^",byte) {self.fail(Token{text:[],start:start as u32,end:(start+1) as u32,..},"asset_wgsl","Invalid WGSL token");return;}pos+=1;if pos<self.input.len && byte!='<' && byte!='>' {let pair=self.input[start..pos+1];for op in ["->","==","!=","&&","||","+=","-=","*=","/=","%=","&=","|=","^=","++","--"] {if pair==op {pos+=1;break;}}}}if self.tokens.len==1000000 {self.fail(Token{text:[],start:start as u32,end:pos as u32,..},"asset_limit","WGSL token count exceeds 1000000");return;}self.record(self.tokens.push(Token{text:self.input[start..pos],start:start as u32,end:pos as u32,number:number}));}if self.failure==Error.none {self.record(self.tokens.push(Token{text:[],start:pos as u32,end:pos as u32,..}));}}
