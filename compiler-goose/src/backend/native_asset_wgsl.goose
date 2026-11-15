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
struct Value {kind:Kind=Kind.unknown,n:f64=0.0,elements:const Value[:] = default<const Value[:]>(),literal:bool=true}
struct Binding {name:const u8[:],value:Value}
struct Field {name:const u8[:],type_name:const u8[:],token:Token}
struct ValueRun {values:Value[:]}
struct Operator {text:const u8[:] = default<const u8[:]>(),precedence:u8=0,count:i64=1}
reusable[] var output_pool:u8[>..]=[];
reusable[] var element_pool:Value[>..]=[];
reusable[] var lane_argument_runs:Value[>..]=[];
fn copyOutput(bytes:const u8[:])->u8[:] {let result=output_pool.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn freeOutput(bytes:const u8[:]) {if bytes.len!=0 {output_pool.free_slice(bytes);}}
fn deinit(result:Result&) {match result {source value=>{freeOutput(value.bytes);},issue value=>{freeOutput(value.value.message);},}result=Result.source{bytes:default<u8[:]>()};}
struct Tokens {storage:Token[:] = default<Token[:]>(),items:Token[:] = default<Token[:]>(),len:i64=0}
reusable[] var pool_Tokens:Token[>..]=[];
reusable[] var token_text_runs:u8[>..]=[];
fn rootedTokenText(text:const u8[:])->const u8[:] {if text.len==0 {return default<const u8[:]>();}return token_text_runs.realloc_slice(text,text.len);}
fn ownTokenText(text:const u8[:])->const u8[:] {if text.len==0 {return default<const u8[:]>();}let owned=token_text_runs.alloc_slice(text.len);for byte,index in text {owned[index]=byte;}return owned;}
fn push(self_:Tokens&,value:Token)->Error {let owned=Token{text:ownTokenText(value.text),start:value.start,end:value.end,number:value.number};let error=blot_support_pooled_buffer::push(self_,owned,pool_Tokens);if error!=blot_error::Error.none && owned.text.len!=0 {token_text_runs.free_slice(owned.text);}self_.len=self_.items.len;return error;}
fn deinit(self_:Tokens&) {for token in self_.items {if token.text.len!=0 {token_text_runs.free_slice(token.text);}}blot_support_pooled_buffer::deinit(self_,pool_Tokens);self_.len=0;}
struct Bindings {storage:Binding[:] = default<Binding[:]>(),items:Binding[:] = default<Binding[:]>(),len:i64=0}
reusable[] var pool_Bindings:Binding[>..]=[];
fn push(self_:Bindings&,value:Binding)->Error {let error=blot_support_pooled_buffer::push(self_,Binding{name:rootedTokenText(value.name),value:rootedValue(value.value)},pool_Bindings);self_.len=self_.items.len;return error;}
fn deinit(self_:Bindings&) {blot_support_pooled_buffer::deinit(self_,pool_Bindings);self_.len=0;}
struct Fields {storage:Field[:] = default<Field[:]>(),items:Field[:] = default<Field[:]>(),len:i64=0}
reusable[] var pool_Fields:Field[>..]=[];
fn push(self_:Fields&,value:Field)->Error {let error=blot_support_pooled_buffer::push(self_,Field{name:rootedTokenText(value.name),type_name:rootedTokenText(value.type_name),token:Token{text:rootedTokenText(value.token.text),start:value.token.start,end:value.token.end,number:value.token.number}},pool_Fields);self_.len=self_.items.len;return error;}
fn deinit(self_:Fields&) {blot_support_pooled_buffer::deinit(self_,pool_Fields);self_.len=0;}
struct Values {storage:Value[:] = default<Value[:]>(),items:Value[:] = default<Value[:]>(),len:i64=0}
reusable[] var pool_Values:Value[>..]=[];
fn push(self_:Values&,value:Value)->Error {let error=blot_support_pooled_buffer::push(self_,rootedValue(value),pool_Values);self_.len=self_.items.len;return error;}
fn deinit(self_:Values&) {blot_support_pooled_buffer::deinit(self_,pool_Values);self_.len=0;}
struct Runs {storage:ValueRun[:] = default<ValueRun[:]>(),items:ValueRun[:] = default<ValueRun[:]>(),len:i64=0}
reusable[] var pool_Runs:ValueRun[>..]=[];
fn push(self_:Runs&,value:ValueRun)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Runs);self_.len=self_.items.len;return error;}
fn deinit(self_:Runs&) {blot_support_pooled_buffer::deinit(self_,pool_Runs);self_.len=0;}
struct Index {table:blot_support_pooled_map::Map<const u8[:],u32> =blot_support_pooled_map::Map<const u8[:],u32>{..}}
reusable[] var slots_Index:dictionary_slot<const u8[:],u32>[>..]=[];
fn get(self_:const Index&,key:const u8[:])->u32? {return blot_support_pooled_map::get(self_.table,key);}
fn insert(self_:Index&,key:const u8[:],value:u32) {blot_support_pooled_map::insert(self_.table,rootedTokenText(key),value,slots_Index);}
fn deinit(self_:Index&) {blot_support_pooled_map::deinit(self_.table,slots_Index);}
struct Aliases {table:blot_support_pooled_map::Map<const u8[:],const u8[:]> =blot_support_pooled_map::Map<const u8[:],const u8[:]>{..}}
reusable[] var slots_Aliases:dictionary_slot<const u8[:],const u8[:]>[>..]=[];
fn get(self_:const Aliases&,key:const u8[:])->const u8[:]? {return blot_support_pooled_map::get(self_.table,key);}
fn insert(self_:Aliases&,key:const u8[:],value:const u8[:]) {blot_support_pooled_map::insert(self_.table,rootedTokenText(key),rootedTokenText(value),slots_Aliases);}
fn deinit(self_:Aliases&) {blot_support_pooled_map::deinit(self_.table,slots_Aliases);}
struct Reader {input:const u8[:],tokens:Tokens=Tokens{..},at:i64=0,visits:i64=0,bindings:Bindings=Bindings{..},binding_index:Index=Index{..},aliases:Aliases=Aliases{..},fields:Fields=Fields{..},parameters:bool=false,constant_mode:bool=false,call_depth:i64=0,header:Text=Text{..},body:Text=Text{..},issue:blot_support::Option<Issue> =blot_support::Option<Issue>{..},runs:Runs=Runs{..},failure:Error=blot_error::Error.none}
fn deinit(self_:Reader&) {for run in self_.runs.items {if run.values.len!=0 {element_pool.free_slice(run.values);}}self_.runs.deinit();self_.tokens.deinit();self_.bindings.deinit();self_.binding_index.deinit();self_.aliases.deinit();self_.fields.deinit();self_.header.deinit();self_.body.deinit();}
fn record(self_:Reader&,error:Error) {if self_.failure==blot_error::Error.none && error!=blot_error::Error.none {self_.failure=error;}}
fn fail(self_:Reader&,token:Token,code:const u8[:],message:const u8[:]) {if self_.failure!=blot_error::Error.none {return;}self_.issue=blot_support::some(Issue{start:token.start,end:token.end,code:code,message:message});self_.failure=blot_error::Error.invalid_asset;}
fn peek(self_:const Reader&)->Token {if self_.at>=self_.tokens.len {return Token{text:default<const u8[:]>(),start:self_.input.len as u32,end:self_.input.len as u32,..};}return self_.tokens.items[self_.at];}
fn syntax(self_:Reader&) {self_.fail(self_.peek(),"asset_wgsl","Malformed WGSL asset");}
fn budget(self_:Reader&,depth:i64)->bool {if self_.failure!=blot_error::Error.none {return false;}self_.visits+=1;if depth>128 || self_.visits>1000000 {self_.fail(self_.peek(),"asset_limit","WGSL asset exceeds the structural budget");return false;}return true;}
fn is(self_:const Reader&,text:const u8[:])->bool {return self_.peek().text==text;}
fn take(self_:Reader&,text:const u8[:])->bool {if self_.failure!=blot_error::Error.none || !self_.is(text) {return false;}self_.at+=1;return true;}
fn expect(self_:Reader&,text:const u8[:]) {if self_.failure==blot_error::Error.none && !self_.take(text) {self_.syntax();}}
fn name(self_:Reader&)->Token {let token=self_.peek();if self_.failure!=blot_error::Error.none {return token;}if token.text.len==0 || !identifierStart(token.text[0]) {self_.syntax();return token;}self_.at+=1;return token;}
fn put(self_:Reader&,out:Text&,text:const u8[:]) {if self_.failure!=blot_error::Error.none {return;}if text.len>limit || out.len>limit-text.len {self_.fail(self_.peek(),"asset_limit","Generated asset module exceeds 16 MiB");return;}self_.record(out.append(text));}
fn elements(self_:Reader&,count:i64)->Value[:] {if self_.failure!=blot_error::Error.none || count==0 {return default<Value[:]>();}let result=element_pool.alloc_slice(count);let error=self_.runs.push(ValueRun{values:result});if error!=blot_error::Error.none {element_pool.free_slice(result);self_.record(error);return default<Value[:]>();}for &value in result {value=Value{..};}return result;}
fn rootedValue(value:Value)->Value {if value.elements.len==0 {return Value{kind:value.kind,n:value.n,literal:value.literal,..};}let elements=element_pool.realloc_slice(value.elements,value.elements.len);return Value{kind:value.kind,n:value.n,elements:elements,literal:value.literal};}
fn ownElements(self_:Reader&,values:const Value[:])->const Value[:] {let result=self_.elements(values.len);if self_.failure!=blot_error::Error.none {return default<const Value[:]>();}for value,index in values {result[index]=rootedValue(value);}return result;}
fn digit(byte:u8)->bool {return byte>='0' && byte<='9';}
fn identifierStart(byte:u8)->bool {return (byte>='a' && byte<='z') || (byte>='A' && byte<='Z') || byte=='_';}
fn identifierContinue(byte:u8)->bool {return identifierStart(byte) || digit(byte);}
fn contains(text:const u8[:],byte:u8)->bool {for item in text {if item==byte {return true;}}return false;}
fn starts(text:const u8[:],prefix:const u8[:])->bool {return text.len>=prefix.len && text[..prefix.len]==prefix;}
fn ends(text:const u8[:],suffix:const u8[:])->bool {return text.len>=suffix.len && text[text.len-suffix.len..]==suffix;}
fn lex(self_:Reader&) {if self_.input.len>limit {self_.fail(Token{text:default<const u8[:]>(),start:0,end:0,..},"asset_limit","WGSL asset exceeds 16 MiB");return;}var unicode:i64=0;while unicode<self_.input.len {let point,length,valid=blot_backend_native_asset_readers::decodePoint(self_.input,unicode);if !valid {self_.fail(Token{text:default<const u8[:]>(),start:0,end:self_.input.len as u32,..},"asset_unicode","WGSL asset must be valid UTF-8");return;}unicode+=length;}var pos:i64=0;while pos<self_.input.len && self_.failure==blot_error::Error.none {let byte=self_.input[pos];if contains(" \t\r\n",byte) {pos+=1;continue;}if starts(self_.input[pos..],"//") {while pos<self_.input.len && self_.input[pos]!='\n' {pos+=1;}continue;}if starts(self_.input[pos..],"/*") {let start=pos;pos+=2;var nesting:i64=1;while pos<self_.input.len && nesting!=0 {if starts(self_.input[pos..],"/*") {nesting+=1;if nesting>128 {self_.fail(Token{text:default<const u8[:]>(),start:start as u32,end:(pos+2) as u32,..},"asset_limit","WGSL comment nesting exceeds 128");return;}pos+=2;}else if starts(self_.input[pos..],"*/") {nesting-=1;pos+=2;}else {pos+=1;}}if nesting!=0 {self_.fail(Token{text:default<const u8[:]>(),start:start as u32,end:pos as u32,..},"asset_wgsl","Unterminated WGSL block comment");return;}continue;}let start=pos;var number=false;if identifierStart(byte) {pos+=1;while pos<self_.input.len && identifierContinue(self_.input[pos]) {pos+=1;}}else if digit(byte) || (byte=='.' && pos+1<self_.input.len && digit(self_.input[pos+1])) {number=true;pos+=1;while pos<self_.input.len {let c=self_.input[pos];if identifierContinue(c) || c=='.' {pos+=1;}else if (c=='+' || c=='-') && pos>start && contains("eEpP",self_.input[pos-1]) {pos+=1;}else {break;}}}else {if !contains("@{}()[]<>,:;.=+-*/%!~&|^",byte) {self_.fail(Token{text:default<const u8[:]>(),start:start as u32,end:(start+1) as u32,..},"asset_wgsl","Invalid WGSL token");return;}pos+=1;if pos<self_.input.len && byte!='<' && byte!='>' {let pair=self_.input[start..pos+1];for op in ["->","==","!=","&&","||","+=","-=","*=","/=","%=","&=","|=","^=","++","--"] {if pair==op {pos+=1;break;}}}}if self_.tokens.len==1000000 {self_.fail(Token{text:default<const u8[:]>(),start:start as u32,end:pos as u32,..},"asset_limit","WGSL token count exceeds 1000000");return;}self_.record(self_.tokens.push(Token{text:self_.input[start..pos],start:start as u32,end:pos as u32,number:number}));}if self_.failure==blot_error::Error.none {self_.record(self_.tokens.push(Token{text:default<const u8[:]>(),start:pos as u32,end:pos as u32,..}));}}

fn attributes(self_:Reader&) {while self_.take("@") {self_.name();if self_.take("(") && !self_.take(")") {while self_.failure==blot_error::Error.none {self_.expression(0,0);if self_.take(")") {break;}self_.expect(",");if self_.take(")") {break;}}}}}
recursive fn typeName(self_:Reader&,depth:i64)->const u8[:] {if !self_.budget(depth) {return default<const u8[:]>();}let token=self_.name();if self_.take("<") {var parameter:i64=0;while self_.failure==blot_error::Error.none {if self_.peek().number || (token.text=="array" && parameter==1) {self_.expression(8,depth+1);}else {self_.typeName(depth+1);}if self_.take(">") {break;}self_.expect(",");parameter+=1;}return default<const u8[:]>();}return token.text;}
fn structure(self_:Reader&) {let token=self_.name();let selected=token.text=="Parameters" && !self_.parameters;if selected {self_.parameters=true;}self_.expect("{");while self_.failure==blot_error::Error.none && !self_.take("}") {self_.attributes();let field=self_.name();self_.expect(":");let type_name=self_.typeName(0);if selected {self_.record(self_.fields.push(Field{name:field.text,type_name:type_name,token:field}));}if self_.take("}") {break;}self_.expect(",");}self_.take(";");}
fn variable(self_:Reader&,is_const:bool,retain:bool) {if self_.take("<") {self_.name();if self_.take(",") {self_.name();}self_.expect(">");}let token=self_.name();if self_.take(":") {self_.typeName(0);}var value=Value{..};if self_.take("=") {let saved=self_.constant_mode;self_.constant_mode=retain;value=self_.expression(0,0);self_.constant_mode=saved;}else if is_const {self_.syntax();return;}self_.expect(";");if retain && self_.failure==blot_error::Error.none {let prior .= self_.binding_index.get(token.text);if prior {self_.bindings.items[prior].value=rootedValue(value);}else {let id=self_.bindings.len as u32;self_.binding_index.insert(token.text,id);self_.record(self_.bindings.push(Binding{name:token.text,value:value}));}}}
fn function(self_:Reader&) {self_.name();self_.expect("(");if !self_.take(")") {while self_.failure==blot_error::Error.none {self_.attributes();self_.name();self_.expect(":");self_.typeName(0);if self_.take(")") {break;}self_.expect(",");if self_.take(")") {break;}}}if self_.take("->") {self_.attributes();self_.typeName(0);}self_.block_(0);}
recursive fn block_(self_:Reader&,depth:i64) {if !self_.budget(depth) {return;}self_.expect("{");while self_.failure==blot_error::Error.none && !self_.take("}") {self_.statement(depth+1);}}
recursive fn statement(self_:Reader&,depth:i64) {if !self_.budget(depth) {return;}self_.attributes();if self_.is("{") {self_.block_(depth+1);return;}if self_.take(";") {return;}if self_.take("var") || self_.take("let") || self_.take("const") {self_.variable(false,false);return;}if self_.take("if") {self_.expression(0,0);self_.block_(depth+1);if self_.take("else") {if self_.is("if") {self_.statement(depth+1);return;}self_.block_(depth+1);}return;}if self_.take("for") {self_.expect("(");if !self_.take(";") {if self_.take("var") || self_.take("let") {self_.variable(false,false);}else {self_.simpleStatement(";");}}if !self_.take(";") {self_.expression(0,0);self_.expect(";");}if !self_.take(")") {self_.simpleStatement(")");}self_.block_(depth+1);return;}if self_.take("while") {self_.expression(0,0);self_.block_(depth+1);return;}if self_.take("loop") || self_.take("continuing") {self_.block_(depth+1);return;}if self_.take("switch") {self_.expression(0,0);self_.expect("{");while self_.failure==blot_error::Error.none && !self_.take("}") {if self_.take("case") {while self_.failure==blot_error::Error.none {if !self_.take("default") {self_.expression(0,0);}if !self_.take(",") {break;}}}else {self_.expect("default");}self_.take(":");self_.block_(depth+1);}return;}if self_.take("return") {if !self_.take(";") {self_.expression(0,0);self_.expect(";");}return;}if self_.take("break") {if self_.take("if") {self_.expression(0,0);}self_.expect(";");return;}if self_.take("continue") || self_.take("discard") {self_.expect(";");return;}if self_.take("const_assert") {self_.expression(0,0);self_.expect(";");return;}self_.simpleStatement(";");}
fn simpleStatement(self_:Reader&,closing:const u8[:]) {self_.expression(0,0);if !self_.take("++") && !self_.take("--") {for op in ["=","+=","-=","*=","/=","%=","&=","|=","^="] {if self_.take(op) {self_.expression(0,0);break;}}}self_.expect(closing);}
fn resolve(self_:const Reader&,original:const u8[:])->const u8[:] {var text=original;for depth in 0..128 {let target .= self_.aliases.get(text);if target {text=target;}else {return text;}}return default<const u8[:]>();}
fn blotName(text:const u8[:])->bool {if text.len==0 || text=="_" || !((text[0]>='a' && text[0]<='z') || text[0]=='_') {return false;}for word in ["const","let","type","data","effect","is","func","do","use","return","yield","break","for","ever","continue","in","case","of","if","then","else","as","import","infix","infixl","infixr","self","where","and","or","true","false"] {if text==word {return false;}}for byte in text {if !identifierContinue(byte) {return false;}}return true;}
fn run(self_:Reader&) {self_.lex();while self_.failure==blot_error::Error.none && !self_.is("") {if !self_.budget(0) {return;}self_.attributes();if self_.take(";") {continue;}if self_.take("struct") {self_.structure();}else if self_.take("alias") || self_.take("type") {let token=self_.name();self_.expect("=");let target=self_.typeName(0);self_.expect(";");if self_.failure==blot_error::Error.none {self_.aliases.insert(token.text,target);}}else if self_.take("const") {self_.variable(true,true);}else if self_.take("var") || self_.take("override") {self_.variable(false,false);}else if self_.take("fn") {self_.function();}else if self_.take("enable") || self_.take("requires") {self_.name();while self_.take(",") {self_.name();}self_.expect(";");}else if self_.take("diagnostic") {self_.expect("(");self_.name();self_.expect(",");self_.name();if self_.take(".") {self_.name();}self_.expect(")");self_.expect(";");}else if self_.take("const_assert") {self_.expression(0,0);self_.expect(";");}else {self_.syntax();}}if self_.failure!=blot_error::Error.none {return;}if self_.parameters {if self_.fields.len>4 {self_.fail(self_.fields.items[4].token,"asset_wgsl_parameters","Parameters must contain at most four f32 fields");return;}self_.put(self_.header,"type Parameters is data = $Parameters { ");for field,index in self_.fields.items {if self_.resolve(field.type_name)!="f32" {self_.fail(field.token,"asset_wgsl_parameters","Parameters fields must resolve to f32");return;}if !blotName(field.name) {self_.fail(field.token,"asset_identifier","WGSL field is not a Blot identifier");return;}if index!=0 {self_.put(self_.header,", ");}self_.put(self_.header,field.name);self_.put(self_.header,": F32");}self_.put(self_.header," }\n");}emitBindings(self_);if self_.header.len>limit-self_.body.len {self_.fail(self_.peek(),"asset_limit","Generated asset module exceeds 16 MiB");}}
fn emitBindings(self_:Reader&) {for binding in self_.bindings.items {if self_.failure!=blot_error::Error.none {return;}let value=binding.value;if !value.literal {continue;}var type_name:const u8[:] = default<const u8[:]>();if value.kind==Kind.f32_value {type_name="F32";}else if value.kind==Kind.u32_value {type_name="U32";}else if value.kind==Kind.boolean {type_name="Bool";}else {continue;}if !blotName(binding.name) {self_.fail(self_.peek(),"asset_identifier","WGSL constant is not a Blot identifier");return;}if !blot_backend_native_asset_numbers::finite(value.n) {self_.fail(self_.peek(),"asset_number","WGSL constant must fit finite F32");return;}self_.put(self_.body,"const ");self_.put(self_.body,binding.name);self_.put(self_.body,": ");self_.put(self_.body,type_name);self_.put(self_.body," = ");if value.kind==Kind.boolean {if value.n!=0.0 {self_.put(self_.body,"true");}else {self_.put(self_.body,"false");}}else if value.kind==Kind.u32_value {emitInteger(self_,value.n as u32);}else {emitFloat(self_,value.n);}self_.put(self_.body,"\n");}}
// Formatting wrappers are outside every recursive expression cycle.
fn emitInteger(self_:Reader&,value:u32) {var bytes:u8[>..<]=[];format(bytes,value);self_.put(self_.body,bytes);}
fn emitFloat(self_:Reader&,value:f64) {var bytes:u8[>..<]=[];blot_backend_native_asset_numbers::float32(bytes,value);self_.put(self_.body,bytes);}
fn constructor(text:const u8[:])->bool {return text=="array" || text=="bitcast" || starts(text,"vec") || starts(text,"mat");}
fn operator(self_:const Reader&)->Operator {let text=self_.peek().text;if (self_.is("<") || self_.is(">")) && self_.at+1<self_.tokens.len {let next=self_.tokens.items[self_.at+1];if next.text==text && next.start==self_.peek().end {if self_.is("<") {return Operator{text:"<<",precedence:8,count:2};}return Operator{text:">>",precedence:8,count:2};}if next.text=="=" {if self_.is("<") {return Operator{text:"<=",precedence:7,count:2};}return Operator{text:">=",precedence:7,count:2};}}let precedences:u8[14]=[1,2,3,4,5,6,6,7,7,9,9,10,10,10];for candidate,index in ["||","&&","|","^","&","==","!=","<",">","+","-","*","/","%"] {if text==candidate {return Operator{text:text,precedence:precedences[index],..};}}return Operator{..};}
recursive fn expression(self_:Reader&,minimum:u8,depth:i64)->Value {if !self_.budget(depth) {return Value{..};}var left=self_.prefix(depth+1);while self_.failure==blot_error::Error.none {let op=self_.operator();if op.precedence==0 || op.precedence<minimum {break;}self_.at+=op.count;let right=self_.expression(op.precedence+1,depth+1);left=self_.binaryValue(op.text,left,right,depth+1);}return left;}
recursive fn prefix(self_:Reader&,depth:i64)->Value {
if !self_.budget(depth) {
return Value{
..}
;
}
let token=self_.peek();
var value=Value{
..}
;
if self_.take("-") || self_.take("+") || self_.take("!") || self_.take("~") || self_.take("&") || self_.take("*") {
let operand=self_.prefix(depth+1);
value=self_.unaryValue(token.text,operand,depth+1);
}
else if self_.take("(") {
value=self_.expression(0,depth+1);
self_.expect(")");
}
else if token.number {
self_.at+=1;
value=self_.literal(token);
}
else {
let name=self_.name();
let spelling=name.text;
if spelling=="true" {
value=Value{
kind:Kind.boolean,n:1.0,..}
;
}
else if spelling=="false" {
value=Value{
kind:Kind.boolean,..}
;
}
else {
let index .= self_.binding_index.get(spelling);
if index {
value=self_.bindings.items[index].value;
}
}
let element_type=if constructor(spelling) && self_.take("<") {
let parsed_type=self_.typeName(depth+1);
while self_.take(",") {
self_.expression(8,depth+1);
}
self_.expect(">");
parsed_type}
else {
self_.input[0..0]}
;
if self_.take("(") {
var args=Values{
..}
;
if !self_.take(")") {
while self_.failure==blot_error::Error.none {
let argument=self_.expression(0,depth+1);
self_.record(args.push(argument));
if self_.take(")") {
break;
}
self_.expect(",");
if self_.take(")") {
break;
}
}
}
let resolved_spelling=self_.resolve(spelling);
if self_.failure==blot_error::Error.none {
value=self_.call(resolved_spelling,element_type,args.items);
}
args.deinit();
}
}
while self_.failure==blot_error::Error.none {
if self_.take("[") {
let index=self_.expression(0,depth+1);
self_.expect("]");
if blot_backend_native_asset_numbers::finite(index.n) && index.n>=0.0 && index.n<value.elements.len as f64 && blot_backend_native_asset_numbers::integral(index.n) {
value=rootedValue(value.elements[index.n as i64]);
}
else {
value=Value{
..}
;
}
}
else if self_.take(".") {
let field=self_.name();
value=self_.swizzle(value,field.text);
}
else {
break;
}
}
return value;
}


fn scalarKind(text:const u8[:])->Kind {if text=="f32" {return Kind.f32_value;}if text=="u32" {return Kind.u32_value;}if text=="i32" {return Kind.i32_value;}if text=="bool" {return Kind.boolean;}if text=="f16" {return Kind.f16_value;}return Kind.unknown;}
fn bits(n:f64)->u32 {if !blot_backend_native_asset_numbers::finite(n) {return 0;}var wrapped=trunc(n)%4294967296.0;if wrapped<0.0 {wrapped+=4294967296.0;}return wrapped as u32;}
fn signed(n:u32)->f64 {if n>=2147483648 {return n as f64-4294967296.0;}return n as f64;}
// Round binary64 directly to binary16, nearest even, avoiding double rounding.
fn half(n:f64)->f64 {let image=blot_native::f64_bits(n);let sign=image&9223372036854775808;let raw=(image>>52)&2047;if raw==2047 {return n;}let exponent=raw as i64-1023;if exponent>15 {return blot_native::f64_from_bits(sign|9218868437227405312);}if exponent< -25 {return blot_native::f64_from_bits(sign);}let significand=(image&4503599627370495)|4503599627370496;var shift:i64=42;if exponent< -14 {shift=28-exponent;}var rounded=significand>>shift;let remainder=significand&((1 as u64<<shift)-1);let midpoint=1 as u64<<(shift-1);if remainder>midpoint || (remainder==midpoint && rounded&1!=0) {rounded+=1;}var result:f64=0.0;if exponent< -14 {result=rounded as f64*0.000000059604644775390625;}else {var e=exponent;if rounded==2048 {rounded=1024;e+=1;}if e>15 {return blot_native::f64_from_bits(sign|9218868437227405312);}result=blot_native::f64_from_bits(((e+1023) as u64<<52)|((rounded-1024)<<42));}return blot_native::f64_from_bits(blot_native::f64_bits(result)|sign);}
fn scalar(kind:Kind,n:f64)->Value {var number=n;if kind==Kind.f32_value {number=(n as! f32) as f64;}else if kind==Kind.f16_value {number=half(n);}else if kind==Kind.u32_value {number=bits(n) as f64;}else if kind==Kind.x32 {number=bits(n) as f64;if n<0.0 {number=signed(bits(n));}}else if kind==Kind.i32_value {number=signed(bits(n));}else if kind==Kind.boolean {number=0.0;if n!=0.0 {number=1.0;}}return Value{kind:kind,n:number,..};}
fn castLane(kind:Kind,value:Value)->Value {if kind==Kind.unknown || value.kind==Kind.unknown {return value;}return scalar(kind,value.n);}
fn boolean(value:bool)->f64 {if value {return 1.0;}return 0.0;}
fn unary(op:const u8[:],value:Value)->Value {if value.kind==Kind.unknown {return Value{..};}if op=="-" {return scalar(value.kind,-value.n);}if op=="+" {return value;}if op=="!" {return scalar(Kind.boolean,boolean(value.n==0.0));}if op=="~" {var kind=value.kind;if kind==Kind.x32 {kind=Kind.i32_value;}return scalar(kind,(~bits(value.n)) as f64);}return Value{..};}
fn promoted(left:Kind,right:Kind)->Kind {if left==Kind.f32_value || right==Kind.f32_value {return Kind.f32_value;}if left==Kind.f16_value || right==Kind.f16_value {return Kind.f16_value;}if left==Kind.u32_value || right==Kind.u32_value {return Kind.u32_value;}if left==Kind.i32_value || right==Kind.i32_value {return Kind.i32_value;}return left;}
fn binary(op:const u8[:],left:Value,right:Value)->Value {if left.kind==Kind.unknown || right.kind==Kind.unknown {return Value{..};}var kind=promoted(left.kind,right.kind);let x=left.n;let y=right.n;var n:f64=0.0;if op=="+" {n=x+y;}else if op=="-" {n=x-y;}else if op=="*" {n=x*y;}else if op=="/" {n=x/y;}else if op=="%" {n=x%y;}else if op=="&" {n=(bits(x)&bits(y)) as f64;}else if op=="|" {n=(bits(x)|bits(y)) as f64;}else if op=="^" {n=(bits(x)^bits(y)) as f64;}else if op=="<<" {n=(bits(x)<<(bits(y)&31)) as f64;}else if op==">>" {let shift=bits(y)&31;var word=bits(x);if kind==Kind.i32_value && word&2147483648!=0 && shift!=0 {word=(word>>shift)|(0xffffffff as u32<<(32-shift));n=signed(word);}else {n=(word>>shift) as f64;}}else {var truth=false;if op=="==" {truth=x==y;}else if op=="!=" {truth=x!=y;}else if op=="<" {truth=x<y;}else if op==">" {truth=x>y;}else if op=="<=" {truth=x<=y;}else if op==">=" {truth=x>=y;}else if op=="&&" {truth=x!=0.0 && y!=0.0;}else if op=="||" {truth=x!=0.0 || y!=0.0;}else {return Value{..};}return scalar(Kind.boolean,boolean(truth));}if kind==Kind.x32 && n<0.0 {kind=Kind.i32_value;}return scalar(kind,n);}
fn hexDigit(byte:u8)->bool {return digit(byte) || (byte>='a' && byte<='f') || (byte>='A' && byte<='F');}
fn parseLiteral(self_:Reader&,token:Token,text:const u8[:],hex:bool,floating_hex:bool)->f64 {var cleaned=Text{..};let result=parseLiteralInto(self_,token,text,hex,floating_hex,cleaned);cleaned.deinit();return result;}
fn parseLiteralInto(self_:Reader&,token:Token,text:const u8[:],hex:bool,floating_hex:bool,cleaned:Text&)->f64 {let hexadecimal=starts(text,"0x") || starts(text,"0X");for byte,index in text {if byte=='_' {var legal=index>0 && index+1<text.len;if legal {if hex && !floating_hex {legal=index>2 && index+1<text.len;}else if hexadecimal {legal=hexDigit(text[index-1]) && hexDigit(text[index+1]);}else {legal=digit(text[index-1]) && digit(text[index+1]);}}if !legal {self_.fail(token,"asset_wgsl","Invalid WGSL number");return 0.0;}continue;}self_.record(cleaned.push(byte));}if self_.failure!=blot_error::Error.none {return 0.0;}if hexadecimal {if floating_hex || !hex {if !contains(cleaned.items,'p') && !contains(cleaned.items,'P') {self_.record(cleaned.append("p0"));}}if self_.failure!=blot_error::Error.none {return 0.0;}let value,valid=blot_backend_native_asset_numbers::hexadecimal(cleaned.items);if !valid {self_.fail(token,"asset_wgsl","Invalid WGSL number");return 0.0;}if floating_hex {return 0.0;}return value;}let value,valid=blot_backend_native_asset_numbers::decimal(cleaned.items);if !valid {self_.fail(token,"asset_wgsl","Invalid WGSL number");return 0.0;}return value;}
fn literal(self_:Reader&,token:Token)->Value {if self_.failure!=blot_error::Error.none {return Value{..};}var text=token.text;var kind=Kind.x32;if text.len==0 {self_.syntax();return Value{..};}let last=text[text.len-1];let hex=starts(text,"0x");let floating_hex=hex && (contains(text,'.') || contains(text,'p') || contains(text,'P'));if last=='u' || last=='i' || ((!hex || floating_hex) && (last=='f' || last=='h')) {text=text[..text.len-1];if last=='u' {kind=Kind.u32_value;}else if last=='i' {kind=Kind.i32_value;}else if last=='f' {kind=Kind.f32_value;}else {kind=Kind.f16_value;}}else if (!hex && (contains(text,'.') || contains(text,'e') || contains(text,'E'))) || floating_hex {kind=Kind.f32_value;}return scalar(kind,self_.parseLiteral(token,text,hex,floating_hex));}
fn swizzle(self_:Reader&,value:Value,text:const u8[:])->Value {if self_.failure!=blot_error::Error.none || text.len==0 || text.len>4 || value.elements.len==0 {return Value{..};}let elements=self_.elements(text.len);if self_.failure!=blot_error::Error.none {return Value{..};}for byte,at in text {var index:i64=99;for symbol,position in "xyzw" {if byte==symbol {index=position;}}for symbol,position in "rgba" {if byte==symbol {index=position;}}if index>=value.elements.len {return Value{..};}elements[at]=rootedValue(value.elements[index]);}if elements.len==1 {return rootedValue(elements[0]);}return Value{elements:elements,..};}
recursive fn unaryValue(self_:Reader&,op:const u8[:],value:Value,depth:i64)->Value {if !self_.budget(depth) {return Value{..};}if value.elements.len==0 {return rootedValue(unary(op,value));}let elements=self_.elements(value.elements.len);if self_.failure!=blot_error::Error.none {return Value{..};}for element,index in value.elements {elements[index]=self_.unaryValue(op,element,depth+1);if self_.failure!=blot_error::Error.none {return Value{..};}}return Value{elements:elements,..};}
fn valueLane(value:Value,index:i64)->Value {if value.elements.len==0 {return value;}return value.elements[index];}
recursive fn binaryValue(self_:Reader&,op:const u8[:],left:Value,right:Value,depth:i64)->Value {if !self_.budget(depth) {return Value{..};}if left.elements.len==0 && right.elements.len==0 {return binary(op,left,right);}let count=max(left.elements.len,right.elements.len);if (left.elements.len!=0 && left.elements.len!=count) || (right.elements.len!=0 && right.elements.len!=count) {return Value{..};}let elements=self_.elements(count);if self_.failure!=blot_error::Error.none {return Value{..};}for index in 0..elements.len {elements[index]=self_.binaryValue(op,valueLane(left,index),valueLane(right,index),depth+1);if self_.failure!=blot_error::Error.none {return Value{..};}}return Value{elements:elements,..};}
recursive fn byteSize(self_:Reader&,value:Value,depth:i64)->i64 {if !self_.budget(depth) {return 0;}if value.elements.len==0 {if value.kind==Kind.f16_value {return 2;}return 4;}var bytes:i64=0;for element in value.elements {let child=self_.byteSize(element,depth+1);if child>0x7fffffffffffffff-bytes {self_.fail(self_.peek(),"asset_limit","WGSL reflected size exceeds the structural budget");return 0;}bytes+=child;}return bytes;}

extern fn acosh(value:f64)->f64;
extern fn asinh(value:f64)->f64;
extern fn atanh(value:f64)->f64;
extern fn sinh(value:f64)->f64;
extern fn tanh(value:f64)->f64;
extern fn exp2(value:f64)->f64;
fn magnitude(value:f64)->f64 {return blot_native::f64_from_bits(blot_native::f64_bits(value)&9223372036854775807);}
recursive fn call(self_:Reader&,name:const u8[:],element_type:const u8[:],args:const Value[:])->Value {if self_.failure!=blot_error::Error.none {return Value{..};}self_.call_depth+=1;if !self_.budget(self_.call_depth) {self_.call_depth-=1;return Value{..};}let result=callInner(self_,name,element_type,args);self_.call_depth-=1;return result;}
fn fillLaneArguments(args:const Value[:],index:i64,lanes:i64,output:Value[:])->bool {for arg,arg_index in args {if arg.elements.len==0 {output[arg_index]=rootedValue(arg);}else if arg.elements.len==lanes {output[arg_index]=rootedValue(arg.elements[index]);}else {return false;}}return true;}
recursive fn callInner(self_:Reader&,name:const u8[:],element_type:const u8[:],args:const Value[:])->Value {
 if name=="bitcast" && args.len==1 {let kind=scalarKind(element_type);if args[0].kind==Kind.unknown {return Value{..};}var representation=bits(args[0].n);if args[0].kind==Kind.f32_value {representation=blot_native::f32_bits(args[0].n as! f32);}var value=scalar(kind,representation as f64);if kind==Kind.f32_value {value=scalar(kind,blot_native::f32_from_bits(representation) as f64);}value.literal=false;return value;}
 if (name=="all" || name=="any") && args.len==1 && args[0].elements.len!=0 {var truth=name=="all";for element in args[0].elements {if element.kind==Kind.unknown {return Value{..};}if name=="all" {truth=truth && element.n!=0.0;}else {truth=truth || element.n!=0.0;}}return scalar(Kind.boolean,boolean(truth));}
 if name=="arrayLength" && args.len==1 && args[0].elements.len!=0 {return scalar(Kind.u32_value,self_.byteSize(args[0],0) as f64);}
 if (name=="dot" || name=="length" || name=="distance") && args.len>=1 && args.len<=2 && args[0].elements.len!=0 {let first=args[0].elements;let dot=name=="dot";let distance=name=="distance";if (dot || distance) && (args.len!=2 || args[1].elements.len!=first.len) {return Value{..};}var sum:f64=0.0;for element,index in first {if element.kind==Kind.unknown {return Value{..};}var x=element.n;var y=x;if dot || distance {let other=args[1].elements[index];if other.kind==Kind.unknown {return Value{..};}if distance {x-=other.n;y=x;}else {y=other.n;}}sum+=x*y;}if !dot {sum=sqrt(sum);}return scalar(first[0].kind,sum);}
 if !constructor(name) && args.len<=4 {var lanes:i64=0;for arg in args {lanes=max(lanes,arg.elements.len);}if lanes!=0 {let elements=self_.elements(lanes);if self_.failure!=blot_error::Error.none {return Value{..};}for &element,index in elements {let lane_args=lane_argument_runs.alloc_slice(args.len);if !fillLaneArguments(args,index,lanes,lane_args) {lane_argument_runs.free_slice(lane_args);return Value{..};}let evaluated=self_.call(name,element_type,lane_args);lane_argument_runs.free_slice(lane_args);element=evaluated;if self_.failure!=blot_error::Error.none {return Value{..};}}return Value{elements:elements,..};}}
 let kind=scalarKind(name);if kind!=Kind.unknown {if args.len==0 {return scalar(kind,0.0);}if args.len!=1 || args[0].kind==Kind.unknown {return Value{..};}return scalar(kind,args[0].n);}
 if name=="array" {return Value{elements:self_.ownElements(args),..};}
 if starts(name,"vec") || starts(name,"mat") {return vector(self_,name,element_type,args);}
 if name=="select" && args.len==3 {if args[2].kind==Kind.unknown {return Value{..};}if args[2].n!=0.0 {return rootedValue(args[1]);}return rootedValue(args[0]);}
 if self_.constant_mode {for unsupported in ["cross","determinant","dot4U8Packed","dot4I8Packed","faceForward","frexp","modf","normalize","reflect","refract","transpose","pack4x8snorm","pack4x8unorm","pack4xI8","pack4xU8","pack2x16snorm","pack2x16unorm","pack2x16float","unpack4x8snorm","unpack4x8unorm","unpack4xI8","unpack4xU8","unpack2x16snorm","unpack2x16unorm","unpack2x16float"] {if name==unsupported {self_.fail(self_.peek(),"asset_wgsl_evaluation","WGSL constant uses an unsupported reflection builtin");return Value{..};}}}
 for arg in args {if arg.kind==Kind.unknown {return Value{..};}}if args.len==0 || args.len>4 {return Value{..};}return builtin(name,args);
}
fn vector(self_:Reader&,name:const u8[:],element_type:const u8[:],args:const Value[:])->Value {var values=Values{..};var lane_kind=scalarKind(element_type);if ends(name,"f") {lane_kind=Kind.f32_value;}if ends(name,"u") {lane_kind=Kind.u32_value;}if ends(name,"i") {lane_kind=Kind.i32_value;}if ends(name,"h") {lane_kind=Kind.f16_value;}for arg in args {if arg.elements.len!=0 {for element in arg.elements {if !self_.budget(0) {break;}self_.record(values.push(castLane(lane_kind,element)));}}else {self_.record(values.push(castLane(lane_kind,arg)));}if self_.failure!=blot_error::Error.none {values.deinit();return Value{..};}}if starts(name,"vec") && name.len>=4 && digit(name[3]) {let lanes=(name[3]-'0') as i64;if values.len==0 {for index in 0..lanes {self_.record(values.push(scalar(lane_kind,0.0)));}}else if values.len==1 {let first=values.items[0];for index in 1..lanes {self_.record(values.push(first));}}}let result=Value{elements:self_.ownElements(values.items),..};values.deinit();return result;}
fn popcount(value:u32)->u32 {var count:u32=0;var rest=value;while rest!=0 {rest&=rest-1;count+=1;}return count;}
fn leadingZeros(value:u32)->u32 {var count:u32=0;var bit:u32=0x80000000;while bit!=0 && value&bit==0 {count+=1;bit>>=1;}return count;}
fn trailingZeros(value:u32)->u32 {var count:u32=0;var bit:u32=1;while bit!=0 && value&bit==0 {count+=1;bit<<=1;}return count;}
fn reverse(value:u32)->u32 {var rest=value;var result:u32=0;for index in 0..32 {result=(result<<1)|(rest&1);rest>>=1;}return result;}
fn builtin(name:const u8[:],args:const Value[:])->Value {let x=args[0].n;var y:f64=0.0;var z:f64=0.0;if args.len>1 {y=args[1].n;}if args.len>2 {z=args[2].n;}var n:f64=0.0;var output_kind=args[0].kind;
 if name=="abs" && args.len==1 {n=magnitude(x);}
 else if name=="acos" && args.len==1 {n=acos(x);}
 else if name=="asin" && args.len==1 {n=asin(x);}
 else if name=="atan" && args.len==1 {n=atan(x);}
 else if name=="atan2" && args.len==2 {n=atan2(x,y);}
 else if name=="acosh" && args.len==1 {n=acosh(x);}
 else if name=="asinh" && args.len==1 {n=asinh(x);}
 else if name=="atanh" && args.len==1 {n=atanh(x);}
 else if name=="cosh" && args.len==1 {n=cos(x);}
 else if name=="sinh" && args.len==1 {n=sinh(x);}
 else if name=="tanh" && args.len==1 {n=tanh(x);}
 else if name=="fma" && args.len==3 {n=x*y+z;}
 else if name=="ldexp" && args.len==2 {n=x*exp2(y);}
 else if name=="quantizeToF16" && args.len==1 {n=half(x);}
 else if name=="length" && args.len==1 {n=magnitude(x);}
 else if name=="distance" && args.len==2 {n=magnitude(x-y);}
 else if name=="dot" && args.len==2 {n=x*y;}
 else if name=="extractBits" && args.len==3 {if args[0].kind!=Kind.i32_value {return Value{..};}let offset=min(bits(y),32 as u32);let count=min(bits(z),32-offset);var mask:u32=0;if count==32 {mask=0xffffffff;}else {mask=(1 as u32<<count)-1;}var extracted:u32=0;if offset!=32 {extracted=(bits(x)>>offset)&mask;}if args[0].kind==Kind.i32_value && count!=0 && count!=32 && extracted&(1 as u32<<(count-1))!=0 {extracted|=~mask;}n=extracted as f64;}
 else if name=="insertBits" && args.len==4 {let offset=min(bits(z),32 as u32);let count=min(bits(args[3].n),32-offset);var mask:u32=0;if count==32 {mask=0xffffffff;}else if offset!=32 {mask=((1 as u32<<count)-1)<<offset;}var inserted=bits(x);if offset!=32 {inserted=(inserted&~mask)|((bits(y)<<offset)&mask);}n=inserted as f64;}
 else if name=="firstTrailingBit" && args.len==1 {var index:u32=0xffffffff;if bits(x)!=0 {index=trailingZeros(bits(x));}n=index as f64;}
 else if name=="firstLeadingBit" && args.len==1 {var integer=bits(x);if args[0].kind==Kind.i32_value && x<0.0 {integer=~integer;}var index:u32=0xffffffff;if integer!=0 {index=31-leadingZeros(integer);}n=index as f64;}
 else if name=="ceil" && args.len==1 {n=ceil(x);}
 else if name=="floor" && args.len==1 {n=floor(x);}
 else if name=="round" && args.len==1 {n=floor(x+0.5);}
 else if name=="trunc" && args.len==1 {n=trunc(x);}
 else if name=="fract" && args.len==1 {n=x-floor(x);}
 else if name=="sqrt" && args.len==1 {n=sqrt(x);}
 else if name=="inverseSqrt" && args.len==1 {n=1.0/sqrt(x);}
 else if name=="sin" && args.len==1 {n=sin(x);}
 else if name=="cos" && args.len==1 {n=cos(x);}
 else if name=="tan" && args.len==1 {n=tan(x);}
 else if name=="exp" && args.len==1 {n=exp(x);}
 else if name=="exp2" && args.len==1 {n=exp2(x);}
 else if name=="log" && args.len==1 {n=log(x);}
 else if name=="log2" && args.len==1 {n=log2(x);}
 else if name=="pow" && args.len==2 {n=pow(x,y);}
 else if name=="min" && args.len==2 {n=floatMin(x,y);}
 else if name=="max" && args.len==2 {n=floatMax(x,y);}
 else if name=="clamp" && args.len==3 {n=floatMin(floatMax(x,y),z);}
 else if name=="saturate" && args.len==1 {n=floatMin(floatMax(x,0.0),1.0);}
 else if name=="mix" && args.len==3 {n=x*(1.0-z)+y*z;}
 else if name=="step" && args.len==2 {if y>=x {n=1.0;}}
 else if name=="smoothstep" && args.len==3 {let t=floatMin(floatMax((z-x)/(y-x),0.0),1.0);n=t*t*(3.0-2.0*t);}
 else if name=="sign" && args.len==1 {if x>0.0 {n=1.0;}if x<0.0 {n= -1.0;}}
 else if name=="radians" && args.len==1 {n=x*(3.141592653589793/180.0);}
 else if name=="degrees" && args.len==1 {n=x*(180.0/3.141592653589793);}
 else if name=="all" || name=="any" {n=x;output_kind=Kind.boolean;}
 else if name=="countOneBits" && args.len==1 {n=popcount(bits(x)) as f64;}
 else if name=="countLeadingZeros" && args.len==1 {n=leadingZeros(bits(x)) as f64;}
 else if name=="countTrailingZeros" && args.len==1 {n=trailingZeros(bits(x)) as f64;}
 else if name=="reverseBits" && args.len==1 {n=reverse(bits(x)) as f64;}
 else {return Value{..};}return scalar(output_kind,n);
}
fn generate(bytes:const u8[:])->Result,Error {var reader=Reader{input:bytes,..};reader.run();if reader.failure!=blot_error::Error.none {let error=reader.failure;if error!=blot_error::Error.invalid_asset {reader.deinit();return Result.source{bytes:default<u8[:]>()},error;}assert(reader.issue.present);var issue=reader.issue.value;issue.message=copyOutput(issue.message);reader.deinit();return Result.issue{value:issue},blot_error::Error.none;}if reader.header.len>0x7fffffffffffffff-reader.body.len {reader.deinit();return Result.source{bytes:default<u8[:]>()},blot_error::Error.out_of_memory;}let source=output_pool.alloc_slice(reader.header.len+reader.body.len);for byte,index in reader.header.items {source[index]=byte;}for byte,index in reader.body.items {source[reader.header.len+index]=byte;}reader.deinit();return Result.source{bytes:source},blot_error::Error.none;}

// Zig's floating @min/@max select the numerical operand when one is NaN.
fn floatMin(a:f64,b:f64)->f64 {if a!=a {return b;}if b!=b {return a;}if a==0.0 && b==0.0 {return blot_native::f64_from_bits(blot_native::f64_bits(a)|blot_native::f64_bits(b));}if b<a {return b;}return a;}
fn floatMax(a:f64,b:f64)->f64 {if a!=a {return b;}if b!=b {return a;}if a==0.0 && b==0.0 {return blot_native::f64_from_bits(blot_native::f64_bits(a)&blot_native::f64_bits(b));}if a<b {return b;}return a;}
