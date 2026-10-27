// Actual source parser for the existing private tuple-array subset. Charges
// semantic token/node/type/edge observations and physical source-byte reads;
// not a complete C09 source/module/type traversal or ordered phase receipt.
namespace static_order_ag_parse;
import lexer;
import lexer_m;
import work;
import static_m_name;
import static_order_b_parse;
import static_product_core;
import static_ag_core;
struct Cursor {lex:lexer_m::State=lexer_m::State {},t:lexer::Token=lexer::Token {},status:i64=0,meter:work::Meter=work::Meter {}}
fn visit(c:Cursor&,event:u32)->bool {if c.status!=0{return false;}let x=work::charge(c.meter,1,event);if x.status!=0 {c.status=if x.status==1 {4} else {5};return false;}return true;}
fn reads(c:Cursor&,n:u64)->bool {if c.status!=0{return false;}let x=work::source_read(c.meter,n);if x.status!=0 {c.status=if x.status==5 {5} else {6};return false;}return true;}
fn advance(s:u8[:],c:Cursor&) {if !visit(c,1){return;}c.lex.meter=c.meter;c.t=lexer_m::next(s,c.lex);c.meter=c.lex.meter;
 if c.lex.work_status!=0 {c.status=if c.lex.work_status==5 {5} else {6};}else if c.t.kind==9 {c.status=1;}}
fn is(s:u8[:],c:Cursor&,t:lexer::Token,k:i64,v:u8[:])->bool {
 if c.status!=0 || t.kind!=k || t.start<0 || t.end<=t.start || t.end>s.len || t.end-t.start!=v.len{return false;}
 for i in v.len {if !reads(c,1){return false;}if s[t.start+i]!=v[i] {return false;}}return true;
}
fn take(s:u8[:],c:Cursor&,k:i64,v:u8[:])->bool {if !is(s,c,c.t,k,v){if c.status==0 {c.status=1;}return false;}advance(s,c);return c.status==0;}
fn part(s:u8[:],c:Cursor&)->static_product_core::Part,bool {
 let start=c.t.start;var end=start;var nest:i64=0;
 while c.status==0 && c.t.kind!=0 {
  if is(s,c,c.t,5,"("){nest+=1;}else if is(s,c,c.t,5,")"){if nest==0 {break;}nest-=1;}
  else if nest==0 && is(s,c,c.t,5,","){break;}end=c.t.end;advance(s,c);
 }
 if c.status!=0 || nest!=0 || start<0 || end<=start || end>s.len{return static_product_core::Part {},false;}
 for ty in [1,2] {
  var own:u8[>..]=[];if ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
  if !reads(c,(end-start) as u64){return static_product_core::Part {},false;}own.append(s[start..end]);own.push('\n');
  var p=static_order_b_parse::parse(own,c.meter);c.meter=p.meter;
  if p.status>=4 {c.status=p.status;return static_product_core::Part {},false;}
  if p.status==0 {if !visit(c,2) || !visit(c,3){return static_product_core::Part {},false;}return static_product_core::Part {start:start,end:end,ty:ty},true;}
 }
 return static_product_core::Part {},false;
}
fn parse(s:u8[:],meter:work::Meter)->static_ag_core::Parsed {
 var lex=lexer_m::init(s,meter);var c=Cursor {lex:lex,meter:lex.meter};
 if lex.work_status!=0 {return static_ag_core::Parsed {status:if lex.work_status==5 {5} else {6},meter:c.meter};}advance(s,c);
 if !take(s,c,1,"static") || !take(s,c,1,"let"){return static_ag_core::Parsed {status:if c.status==0 {1} else {c.status},meter:c.meter};}
 let name=c.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len{return static_ag_core::Parsed {meter:c.meter};}
 let named=static_m_name::check(s[name.start..name.end],c.meter);if named.work_status!=0 {return static_ag_core::Parsed {status:if named.work_status==5 {5} else {6},meter:c.meter};}
 if !named.valid{return static_ag_core::Parsed {meter:c.meter};}advance(s,c);if !take(s,c,5,"="){return static_ag_core::Parsed {status:c.status,meter:c.meter};}
 var array=false;if is(s,c,c.t,5,"#") {advance(s,c);if !take(s,c,5,"["){return static_ag_core::Parsed {status:c.status,meter:c.meter};}array=true;}
 var parts:static_product_core::Part[>..]=[];var width:i64=0;var rows:i64=0;var types:i64[16]=[0;16];
 loop {
  if !take(s,c,5,"("){return static_ag_core::Parsed {status:if c.status==0 {1} else {c.status},meter:c.meter};}var count:i64=0;
  loop {
   if count>=16 || parts.len>=100000{return static_ag_core::Parsed {status:2,meter:c.meter};}
   let item,ok=part(s,c);if !ok{return static_ag_core::Parsed {status:if c.status==0 {1} else {c.status},meter:c.meter};}
   if !visit(c,6) {return static_ag_core::Parsed {status:c.status,meter:c.meter};}
   if rows==0 {types[count]=item.ty;}else if count>=width || types[count]!=item.ty{return static_ag_core::Parsed {meter:c.meter};}
   parts.push(item);count+=1;if is(s,c,c.t,5,",") {advance(s,c);}else {break;}
  }
  if count<2 || !take(s,c,5,")") || (rows>0 && count!=width){return static_ag_core::Parsed {status:if c.status==0 {1} else {c.status},meter:c.meter};}
  if rows==0 {width=count;}rows+=1;if !array || !is(s,c,c.t,5,","){break;}advance(s,c);
 }
 if array && !take(s,c,5,"]"){return static_ag_core::Parsed {status:if c.status==0 {1} else {c.status},meter:c.meter};}
 while c.status==0 && c.t.kind==6 {advance(s,c);}if c.status!=0 || c.t.kind!=0{return static_ag_core::Parsed {status:if c.status==0 {1} else {c.status},meter:c.meter};}
 if !reads(c,s.len as u64) {return static_ag_core::Parsed {status:c.status,meter:c.meter};}
 return static_ag_core::Parsed {status:0,meter:c.meter,tree:static_product_core::Tree {source:s,name_start:name.start,name_end:name.end,is_array:array,width:width,rows:rows,parts:parts}};
}
