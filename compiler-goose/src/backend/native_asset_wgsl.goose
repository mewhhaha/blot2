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

fn attributes(self:Reader&) {while self.take("@") {self.name();if self.take("(") && !self.take(")") {while self.failure==Error.none {self.expression(0,0);if self.take(")") {break;}self.expect(",");if self.take(")") {break;}}}}}
fn typeName(self:Reader&,depth:i64)->const u8[:] {if !self.budget(depth) {return [];}let token=self.name();if self.take("<") {var parameter:i64=0;while self.failure==Error.none {if self.peek().number || (token.text=="array" && parameter==1) {self.expression(8,depth+1);}else {self.typeName(depth+1);}if self.take(">") {break;}self.expect(",");parameter+=1;}return [];}return token.text;}
fn structure(self:Reader&) {let token=self.name();let selected=token.text=="Parameters" && !self.parameters;if selected {self.parameters=true;}self.expect("{");while self.failure==Error.none && !self.take("}") {self.attributes();let field=self.name();self.expect(":");let type_name=self.typeName(0);if selected {self.record(self.fields.push(Field{name:field.text,type_name:type_name,token:field}));}if self.take("}") {break;}self.expect(",");}self.take(";");}
fn variable(self:Reader&,is_const:bool,retain:bool) {if self.take("<") {self.name();if self.take(",") {self.name();}self.expect(">");}let token=self.name();if self.take(":") {self.typeName(0);}var value=Value{..};if self.take("=") {let saved=self.constant_mode;self.constant_mode=retain;value=self.expression(0,0);self.constant_mode=saved;}else if is_const {self.syntax();return;}self.expect(";");if retain && self.failure==Error.none {let prior .= self.binding_index.get(token.text);if prior {self.bindings.items[prior].value=value;}else {let id=self.bindings.len as u32;self.binding_index.insert(token.text,id);self.record(self.bindings.push(Binding{name:token.text,value:value}));}}}
fn function(self:Reader&) {self.name();self.expect("(");if !self.take(")") {while self.failure==Error.none {self.attributes();self.name();self.expect(":");self.typeName(0);if self.take(")") {break;}self.expect(",");if self.take(")") {break;}}}if self.take("->") {self.attributes();self.typeName(0);}self.block(0);}
fn block(self:Reader&,depth:i64) {if !self.budget(depth) {return;}self.expect("{");while self.failure==Error.none && !self.take("}") {self.statement(depth+1);}}
fn statement(self:Reader&,depth:i64) {if !self.budget(depth) {return;}self.attributes();if self.is("{") {self.block(depth+1);return;}if self.take(";") {return;}if self.take("var") || self.take("let") || self.take("const") {self.variable(false,false);return;}if self.take("if") {self.expression(0,0);self.block(depth+1);if self.take("else") {if self.is("if") {self.statement(depth+1);return;}self.block(depth+1);}return;}if self.take("for") {self.expect("(");if !self.take(";") {if self.take("var") || self.take("let") {self.variable(false,false);}else {self.simpleStatement(";");}}if !self.take(";") {self.expression(0,0);self.expect(";");}if !self.take(")") {self.simpleStatement(")");}self.block(depth+1);return;}if self.take("while") {self.expression(0,0);self.block(depth+1);return;}if self.take("loop") || self.take("continuing") {self.block(depth+1);return;}if self.take("switch") {self.expression(0,0);self.expect("{");while self.failure==Error.none && !self.take("}") {if self.take("case") {while self.failure==Error.none {if !self.take("default") {self.expression(0,0);}if !self.take(",") {break;}}}else {self.expect("default");}self.take(":");self.block(depth+1);}return;}if self.take("return") {if !self.take(";") {self.expression(0,0);self.expect(";");}return;}if self.take("break") {if self.take("if") {self.expression(0,0);}self.expect(";");return;}if self.take("continue") || self.take("discard") {self.expect(";");return;}if self.take("const_assert") {self.expression(0,0);self.expect(";");return;}self.simpleStatement(";");}
fn simpleStatement(self:Reader&,closing:const u8[:]) {self.expression(0,0);if !self.take("++") && !self.take("--") {for op in ["=","+=","-=","*=","/=","%=","&=","|=","^="] {if self.take(op) {self.expression(0,0);break;}}}self.expect(closing);}
fn resolve(self:const Reader&,original:const u8[:])->const u8[:] {var text=original;for depth in 0..128 {let target .= self.aliases.get(text);if target {text=target;}else {return text;}}return [];}
fn blotName(text:const u8[:])->bool {if text.len==0 || text=="_" || !((text[0]>='a' && text[0]<='z') || text[0]=='_') {return false;}for word in ["const","let","type","data","effect","is","func","do","use","return","yield","break","for","ever","continue","in","case","of","if","then","else","as","import","infix","infixl","infixr","self","where","and","or","true","false"] {if text==word {return false;}}for byte in text {if !identifierContinue(byte) {return false;}}return true;}
fn run(self:Reader&) {self.lex();while self.failure==Error.none && !self.is("") {if !self.budget(0) {return;}self.attributes();if self.take(";") {continue;}if self.take("struct") {self.structure();}else if self.take("alias") || self.take("type") {let token=self.name();self.expect("=");let target=self.typeName(0);self.expect(";");if self.failure==Error.none {self.aliases.insert(token.text,target);}}else if self.take("const") {self.variable(true,true);}else if self.take("var") || self.take("override") {self.variable(false,false);}else if self.take("fn") {self.function();}else if self.take("enable") || self.take("requires") {self.name();while self.take(",") {self.name();}self.expect(";");}else if self.take("diagnostic") {self.expect("(");self.name();self.expect(",");self.name();if self.take(".") {self.name();}self.expect(")");self.expect(";");}else if self.take("const_assert") {self.expression(0,0);self.expect(";");}else {self.syntax();}}if self.failure!=Error.none {return;}if self.parameters {if self.fields.len>4 {self.fail(self.fields.items[4].token,"asset_wgsl_parameters","Parameters must contain at most four f32 fields");return;}self.put(self.header,"type Parameters is data = $Parameters { ");for field,index in self.fields.items {if self.resolve(field.type_name)!="f32" {self.fail(field.token,"asset_wgsl_parameters","Parameters fields must resolve to f32");return;}if !blotName(field.name) {self.fail(field.token,"asset_identifier","WGSL field is not a Blot identifier");return;}if index!=0 {self.put(self.header,", ");}self.put(self.header,field.name);self.put(self.header,": F32");}self.put(self.header," }\n");}emitBindings(self);if self.header.len>limit-self.body.len {self.fail(self.peek(),"asset_limit","Generated asset module exceeds 16 MiB");}}
fn emitBindings(self:Reader&) {for binding in self.bindings.items {if self.failure!=Error.none {return;}let value=binding.value;if !value.literal {continue;}var type_name:const u8[:]=[];if value.kind==Kind.f32_value {type_name="F32";}else if value.kind==Kind.u32_value {type_name="U32";}else if value.kind==Kind.boolean {type_name="Bool";}else {continue;}if !blotName(binding.name) {self.fail(self.peek(),"asset_identifier","WGSL constant is not a Blot identifier");return;}if !blot_backend_native_asset_numbers::finite(value.n) {self.fail(self.peek(),"asset_number","WGSL constant must fit finite F32");return;}self.put(self.body,"const ");self.put(self.body,binding.name);self.put(self.body,": ");self.put(self.body,type_name);self.put(self.body," = ");if value.kind==Kind.boolean {if value.n!=0.0 {self.put(self.body,"true");}else {self.put(self.body,"false");}}else if value.kind==Kind.u32_value {emitInteger(self,value.n as u32);}else {emitFloat(self,value.n);}self.put(self.body,"\n");}}
// Formatting wrappers are outside every recursive expression cycle.
fn emitInteger(self:Reader&,value:u32) {var bytes:u8[>..<]=[];format(bytes,value);self.put(self.body,bytes);}
fn emitFloat(self:Reader&,value:f64) {var bytes:u8[>..<]=[];blot_backend_native_asset_numbers::float32(bytes,value);self.put(self.body,bytes);}
fn constructor(text:const u8[:])->bool {return text=="array" || text=="bitcast" || starts(text,"vec") || starts(text,"mat");}
fn operator(self:const Reader&)->Operator {let text=self.peek().text;if (self.is("<") || self.is(">")) && self.at+1<self.tokens.len {let next=self.tokens.items[self.at+1];if next.text==text && next.start==self.peek().end {if self.is("<") {return Operator{text:"<<",precedence:8,count:2};}return Operator{text:">>",precedence:8,count:2};}if next.text=="=" {if self.is("<") {return Operator{text:"<=",precedence:7,count:2};}return Operator{text:">=",precedence:7,count:2};}}let precedences:u8[14]=[1,2,3,4,5,6,6,7,7,9,9,10,10,10];for candidate,index in ["||","&&","|","^","&","==","!=","<",">","+","-","*","/","%"] {if text==candidate {return Operator{text:text,precedence:precedences[index],..};}}return Operator{..};}
fn expression(self:Reader&,minimum:u8,depth:i64)->Value {if !self.budget(depth) {return Value{..};}var left=self.prefix(depth+1);while self.failure==Error.none {let op=self.operator();if op.precedence==0 || op.precedence<minimum {break;}self.at+=op.count;let right=self.expression(op.precedence+1,depth+1);left=self.binaryValue(op.text,left,right,depth+1);}return left;}
fn prefix(self:Reader&,depth:i64)->Value {if !self.budget(depth) {return Value{..};}let token=self.peek();var value=Value{..};if self.take("-") || self.take("+") || self.take("!") || self.take("~") || self.take("&") || self.take("*") {let operand=self.prefix(depth+1);value=self.unaryValue(token.text,operand,depth+1);}else if self.take("(") {value=self.expression(0,depth+1);self.expect(")");}else if token.number {self.at+=1;value=self.literal(token);}else {let name=self.name();var spelling=name.text;if spelling=="true" {value=Value{kind:Kind.boolean,n:1.0,..};}else if spelling=="false" {value=Value{kind:Kind.boolean,..};}else {let index .= self.binding_index.get(spelling);if index {value=self.bindings.items[index].value;}}var element_type:const u8[:]=[];if constructor(spelling) && self.take("<") {element_type=self.typeName(depth+1);while self.take(",") {self.expression(8,depth+1);}self.expect(">");}if self.take("(") {var args=Values{..};if !self.take(")") {while self.failure==Error.none {let argument=self.expression(0,depth+1);self.record(args.push(argument));if self.take(")") {break;}self.expect(",");if self.take(")") {break;}}}spelling=self.resolve(spelling);if self.failure==Error.none {value=self.call(spelling,element_type,args.items);}args.deinit();}}while self.failure==Error.none {if self.take("[") {let index=self.expression(0,depth+1);self.expect("]");if blot_backend_native_asset_numbers::finite(index.n) && index.n>=0.0 && index.n<value.elements.len as f64 && blot_backend_native_asset_numbers::integral(index.n) {value=value.elements[index.n as i64];}else {value=Value{..};}}else if self.take(".") {let field=self.name();value=self.swizzle(value,field.text);}else {break;}}return value;}

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
fn parseLiteral(self:Reader&,token:Token,text:const u8[:],hex:bool,floating_hex:bool)->f64 {var cleaned=Text{..};let result=parseLiteralInto(self,token,text,hex,floating_hex,cleaned);cleaned.deinit();return result;}
fn parseLiteralInto(self:Reader&,token:Token,text:const u8[:],hex:bool,floating_hex:bool,cleaned:Text&)->f64 {let hexadecimal=starts(text,"0x") || starts(text,"0X");for byte,index in text {if byte=='_' {var legal=index>0 && index+1<text.len;if legal {if hex && !floating_hex {legal=index>2 && index+1<text.len;}else if hexadecimal {legal=hexDigit(text[index-1]) && hexDigit(text[index+1]);}else {legal=digit(text[index-1]) && digit(text[index+1]);}}if !legal {self.fail(token,"asset_wgsl","Invalid WGSL number");return 0.0;}continue;}self.record(cleaned.push(byte));}if self.failure!=Error.none {return 0.0;}if hexadecimal {if floating_hex || !hex {if !contains(cleaned.items,'p') && !contains(cleaned.items,'P') {self.record(cleaned.append("p0"));}}if self.failure!=Error.none {return 0.0;}let value,valid=blot_backend_native_asset_numbers::hexadecimal(cleaned.items);if !valid {self.fail(token,"asset_wgsl","Invalid WGSL number");return 0.0;}if floating_hex {return 0.0;}return value;}let value,valid=blot_backend_native_asset_numbers::decimal(cleaned.items);if !valid {self.fail(token,"asset_wgsl","Invalid WGSL number");return 0.0;}return value;}
fn literal(self:Reader&,token:Token)->Value {if self.failure!=Error.none {return Value{..};}var text=token.text;var kind=Kind.x32;if text.len==0 {self.syntax();return Value{..};}let last=text[text.len-1];let hex=starts(text,"0x");let floating_hex=hex && (contains(text,'.') || contains(text,'p') || contains(text,'P'));if last=='u' || last=='i' || ((!hex || floating_hex) && (last=='f' || last=='h')) {text=text[..text.len-1];if last=='u' {kind=Kind.u32_value;}else if last=='i' {kind=Kind.i32_value;}else if last=='f' {kind=Kind.f32_value;}else {kind=Kind.f16_value;}}else if (!hex && (contains(text,'.') || contains(text,'e') || contains(text,'E'))) || floating_hex {kind=Kind.f32_value;}return scalar(kind,self.parseLiteral(token,text,hex,floating_hex));}
fn swizzle(self:Reader&,value:Value,text:const u8[:])->Value {if self.failure!=Error.none || text.len==0 || text.len>4 || value.elements.len==0 {return Value{..};}let elements=self.elements(text.len);if self.failure!=Error.none {return Value{..};}for byte,at in text {var index:i64=99;for symbol,position in "xyzw" {if byte==symbol {index=position;}}for symbol,position in "rgba" {if byte==symbol {index=position;}}if index>=value.elements.len {return Value{..};}elements[at]=value.elements[index];}if elements.len==1 {return elements[0];}return Value{elements:elements,..};}
fn unaryValue(self:Reader&,op:const u8[:],value:Value,depth:i64)->Value {if !self.budget(depth) {return Value{..};}if value.elements.len==0 {return unary(op,value);}let elements=self.elements(value.elements.len);if self.failure!=Error.none {return Value{..};}for element,index in value.elements {elements[index]=self.unaryValue(op,element,depth+1);if self.failure!=Error.none {return Value{..};}}return Value{elements:elements,..};}
fn binaryValue(self:Reader&,op:const u8[:],left:Value,right:Value,depth:i64)->Value {if !self.budget(depth) {return Value{..};}if left.elements.len==0 && right.elements.len==0 {return binary(op,left,right);}let count=max(left.elements.len,right.elements.len);if (left.elements.len!=0 && left.elements.len!=count) || (right.elements.len!=0 && right.elements.len!=count) {return Value{..};}let elements=self.elements(count);if self.failure!=Error.none {return Value{..};}for &element,index in elements {var a=left;var b=right;if left.elements.len!=0 {a=left.elements[index];}if right.elements.len!=0 {b=right.elements[index];}element=self.binaryValue(op,a,b,depth+1);if self.failure!=Error.none {return Value{..};}}return Value{elements:elements,..};}
fn byteSize(self:Reader&,value:Value,depth:i64)->i64 {if !self.budget(depth) {return 0;}if value.elements.len==0 {if value.kind==Kind.f16_value {return 2;}return 4;}var bytes:i64=0;for element in value.elements {let child=self.byteSize(element,depth+1);if child>0x7fffffffffffffff-bytes {self.fail(self.peek(),"asset_limit","WGSL reflected size exceeds the structural budget");return 0;}bytes+=child;}return bytes;}

extern fn acosh(value:f64)->f64;
extern fn asinh(value:f64)->f64;
extern fn atanh(value:f64)->f64;
extern fn sinh(value:f64)->f64;
extern fn tanh(value:f64)->f64;
extern fn exp2(value:f64)->f64;
fn magnitude(value:f64)->f64 {return blot_native::f64_from_bits(blot_native::f64_bits(value)&9223372036854775807);}
fn call(self:Reader&,name:const u8[:],element_type:const u8[:],args:const Value[:])->Value {if self.failure!=Error.none {return Value{..};}self.call_depth+=1;var result=Value{..};if self.budget(self.call_depth) {result=callInner(self,name,element_type,args);}self.call_depth-=1;return result;}
fn callInner(self:Reader&,name:const u8[:],element_type:const u8[:],args:const Value[:])->Value {
 if name=="bitcast" && args.len==1 {let kind=scalarKind(element_type);if args[0].kind==Kind.unknown {return Value{..};}var representation=bits(args[0].n);if args[0].kind==Kind.f32_value {representation=blot_native::f32_bits(args[0].n as! f32);}var value=scalar(kind,representation as f64);if kind==Kind.f32_value {value=scalar(kind,blot_native::f32_from_bits(representation) as f64);}value.literal=false;return value;}
 if (name=="all" || name=="any") && args.len==1 && args[0].elements.len!=0 {var truth=name=="all";for element in args[0].elements {if element.kind==Kind.unknown {return Value{..};}if name=="all" {truth=truth && element.n!=0.0;}else {truth=truth || element.n!=0.0;}}return scalar(Kind.boolean,boolean(truth));}
 if name=="arrayLength" && args.len==1 && args[0].elements.len!=0 {return scalar(Kind.u32_value,self.byteSize(args[0],0) as f64);}
 if (name=="dot" || name=="length" || name=="distance") && args.len>=1 && args.len<=2 && args[0].elements.len!=0 {let first=args[0].elements;let dot=name=="dot";let distance=name=="distance";if (dot || distance) && (args.len!=2 || args[1].elements.len!=first.len) {return Value{..};}var sum:f64=0.0;for element,index in first {if element.kind==Kind.unknown {return Value{..};}var x=element.n;var y=x;if dot || distance {let other=args[1].elements[index];if other.kind==Kind.unknown {return Value{..};}if distance {x-=other.n;y=x;}else {y=other.n;}}sum+=x*y;}if !dot {sum=sqrt(sum);}return scalar(first[0].kind,sum);}
 if !constructor(name) && args.len<=4 {var lanes:i64=0;for arg in args {lanes=max(lanes,arg.elements.len);}if lanes!=0 {let elements=self.elements(lanes);if self.failure!=Error.none {return Value{..};}for &element,index in elements {var lane_args:Value[4]=[Value{..};4];for arg,arg_index in args {if arg.elements.len==0 {lane_args[arg_index]=arg;}else if arg.elements.len==lanes {lane_args[arg_index]=arg.elements[index];}else {return Value{..};}}element=self.call(name,element_type,lane_args[..args.len]);if self.failure!=Error.none {return Value{..};}}return Value{elements:elements,..};}}
 let kind=scalarKind(name);if kind!=Kind.unknown {if args.len==0 {return scalar(kind,0.0);}if args.len!=1 || args[0].kind==Kind.unknown {return Value{..};}return scalar(kind,args[0].n);}
 if name=="array" {return Value{elements:self.ownElements(args),..};}
 if starts(name,"vec") || starts(name,"mat") {return vector(self,name,element_type,args);}
 if name=="select" && args.len==3 {if args[2].kind==Kind.unknown {return Value{..};}if args[2].n!=0.0 {return args[1];}return args[0];}
 if self.constant_mode {for unsupported in ["cross","determinant","dot4U8Packed","dot4I8Packed","faceForward","frexp","modf","normalize","reflect","refract","transpose","pack4x8snorm","pack4x8unorm","pack4xI8","pack4xU8","pack2x16snorm","pack2x16unorm","pack2x16float","unpack4x8snorm","unpack4x8unorm","unpack4xI8","unpack4xU8","unpack2x16snorm","unpack2x16unorm","unpack2x16float"] {if name==unsupported {self.fail(self.peek(),"asset_wgsl_evaluation","WGSL constant uses an unsupported reflection builtin");return Value{..};}}}
 for arg in args {if arg.kind==Kind.unknown {return Value{..};}}if args.len==0 || args.len>4 {return Value{..};}return builtin(name,args);
}
fn vector(self:Reader&,name:const u8[:],element_type:const u8[:],args:const Value[:])->Value {var values=Values{..};var lane_kind=scalarKind(element_type);if ends(name,"f") {lane_kind=Kind.f32_value;}if ends(name,"u") {lane_kind=Kind.u32_value;}if ends(name,"i") {lane_kind=Kind.i32_value;}if ends(name,"h") {lane_kind=Kind.f16_value;}for arg in args {if arg.elements.len!=0 {for element in arg.elements {if !self.budget(0) {break;}self.record(values.push(castLane(lane_kind,element)));}}else {self.record(values.push(castLane(lane_kind,arg)));}if self.failure!=Error.none {values.deinit();return Value{..};}}if starts(name,"vec") && name.len>=4 && digit(name[3]) {let lanes=(name[3]-'0') as i64;if values.len==0 {for index in 0..lanes {self.record(values.push(scalar(lane_kind,0.0)));}}else if values.len==1 {let first=values.items[0];for index in 1..lanes {self.record(values.push(first));}}}let result=Value{elements:self.ownElements(values.items),..};values.deinit();return result;}
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
fn generate(bytes:const u8[:])->Result,Error {var reader=Reader{input:bytes,..};reader.run();if reader.failure!=Error.none {let error=reader.failure;if error!=Error.invalid_asset {reader.deinit();return Result.source{bytes:[]},error;}assert(reader.issue.present);var issue=reader.issue.value;issue.message=copyOutput(issue.message);reader.deinit();return Result.issue{value:issue},Error.none;}if reader.header.len>0x7fffffffffffffff-reader.body.len {reader.deinit();return Result.source{bytes:[]},Error.out_of_memory;}let source=output_pool.alloc_slice(reader.header.len+reader.body.len);for byte,index in reader.header.items {source[index]=byte;}for byte,index in reader.body.items {source[reader.header.len+index]=byte;}reader.deinit();return Result.source{bytes:source},Error.none;}

// Zig's floating @min/@max select the numerical operand when one is NaN.
fn floatMin(a:f64,b:f64)->f64 {if a!=a {return b;}if b!=b {return a;}if a==0.0 && b==0.0 {return blot_native::f64_from_bits(blot_native::f64_bits(a)|blot_native::f64_bits(b));}if b<a {return b;}return a;}
fn floatMax(a:f64,b:f64)->f64 {if a!=a {return b;}if b!=b {return a;}if a==0.0 && b==0.0 {return blot_native::f64_from_bits(blot_native::f64_bits(a)&blot_native::f64_bits(b));}if a<b {return b;}return a;}
