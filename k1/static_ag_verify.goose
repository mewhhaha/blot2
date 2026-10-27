// Independently replay aggregate source under the same partial work meter.
// Optional exact-source scalar cache replays cold phase totals on hits.
namespace static_ag_verify;
import lexer;
import lexer_m;
import work;
import static_m_name;
import static_b_parse;
import static_b_verify;
import static_product_core;
import static_ag_core;
struct Reader {lex:lexer_m::State=lexer_m::State {},t:lexer::Token=lexer::Token {},status:i64=0,meter:work::Meter=work::Meter {}}
struct Slot {start:i64= -1,end:i64=0,ty:i64=0,p1:u32=0,p2:u32=0}
fn visit(r:Reader&,event:u32)->bool {if r.status!=0{return false;}let x=work::charge(r.meter,2,event);if x.status!=0 {r.status=if x.status==1 {4} else {5};return false;}return true;}
fn reads(r:Reader&,n:u64)->bool {if r.status!=0{return false;}let x=work::source_read(r.meter,n);if x.status!=0 {r.status=if x.status==5 {5} else {6};return false;}return true;}
fn advance(s:u8[:],r:Reader&) {if !visit(r,1){return;}r.lex.meter=r.meter;r.t=lexer_m::next(s,r.lex);r.meter=r.lex.meter;
 if r.lex.work_status!=0 {r.status=if r.lex.work_status==5 {5} else {6};}else if r.t.kind==9 {r.status=1;}}
fn is(s:u8[:],r:Reader&,t:lexer::Token,k:i64,v:u8[:])->bool {
 if r.status!=0 || t.kind!=k || t.start<0 || t.end<=t.start || t.end>s.len || t.end-t.start!=v.len{return false;}
 for i in v.len {if !reads(r,1){return false;}if s[t.start+i]!=v[i] {return false;}}return true;
}
fn word(s:u8[:],r:Reader&,k:i64,v:u8[:])->bool {if !is(s,r,r.t,k,v){if r.status==0 {r.status=1;}return false;}advance(s,r);return r.status==0;}
fn equal(s:u8[:],r:Reader&,a:i64,ae:i64,b:i64,be:i64)->bool {
 if a<0 || b<0 || ae<a || be<b || ae>s.len || be>s.len || ae-a!=be-b{return false;}
 for i in ae-a {if !reads(r,2){return false;}if s[a+i]!=s[b+i]{return false;}}return true;
}
fn replay(r:Reader&,phase:u32,count:u32)->bool {for _ in count {let q=work::charge(r.meter,phase,1);if q.status!=0 {r.status=if q.status==1 {4} else {5};return false;}}return true;}
fn verify(source:u8[:],p:static_product_core::Tree&,meter:work::Meter,cached:bool)->static_ag_core::Checked {
 if source.len>16777216 || p.source.len!=source.len || p.rows<1 || p.width<2 || p.width>16 || p.parts.len>100000 ||
   p.rows>100000/p.width || p.parts.len!=p.rows*p.width {return static_ag_core::Checked {meter:meter};}
 var initial=meter;for i in source.len {let q=work::source_read(initial,2);if q.status!=0{return static_ag_core::Checked {status:if q.status==5 {5} else {6},meter:initial};}
  if source[i]!=p.source[i]{return static_ag_core::Checked {meter:initial};}}
 var lex=lexer_m::init(source,initial);var r=Reader {lex:lex,meter:lex.meter};if lex.work_status!=0{return static_ag_core::Checked {status:if lex.work_status==5 {5} else {6},meter:r.meter};}
 advance(source,r);if !word(source,r,1,"static") || !word(source,r,1,"let") {return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
 let name=r.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>source.len || name.start!=p.name_start || name.end!=p.name_end {return static_ag_core::Checked {meter:r.meter};}
 let named=static_m_name::check(source[name.start..name.end],r.meter);if named.work_status!=0 {return static_ag_core::Checked {status:if named.work_status==5 {5} else {6},meter:r.meter};}
 if !named.valid{return static_ag_core::Checked {meter:r.meter};}advance(source,r);if !word(source,r,5,"="){return static_ag_core::Checked {status:r.status,meter:r.meter};}
 if p.is_array && (!word(source,r,5,"#") || !word(source,r,5,"[")){return static_ag_core::Checked {status:r.status,meter:r.meter};}
 if !p.is_array && p.rows!=1{return static_ag_core::Checked {meter:r.meter};}
 var a=Slot {};var b=Slot {};var next:i64=0;
 for row in p.rows {
  if !word(source,r,5,"("){return static_ag_core::Checked {status:r.status,meter:r.meter};}
  for col in p.width {
   if !visit(r,2) || !visit(r,3){return static_ag_core::Checked {status:r.status,meter:r.meter};}
   let item=p.parts[row*p.width+col];let begin=r.t.start;var end=begin;var depth:i64=0;
   while r.status==0 && r.t.kind!=0 {
    if is(source,r,r.t,5,"("){depth+=1;}else if is(source,r,r.t,5,")"){if depth==0 {break;}depth-=1;}
    else if depth==0 && is(source,r,r.t,5,","){break;}end=r.t.end;advance(source,r);
   }
   if r.status!=0{return static_ag_core::Checked {status:r.status,meter:r.meter};}
   if !visit(r,6){return static_ag_core::Checked {status:r.status,meter:r.meter};}
   if depth!=0 || begin<0 || end<=begin || end>source.len || begin!=item.start || end!=item.end || (item.ty!=1 && item.ty!=2) {return static_ag_core::Checked {meter:r.meter};}
   if row>0 {if !visit(r,3) || !visit(r,6){return static_ag_core::Checked {status:r.status,meter:r.meter};}if item.ty!=p.parts[col].ty{return static_ag_core::Checked {meter:r.meter};}}
   var hit:i64= -1;
   if cached && item.ty==a.ty && equal(source,r,a.start,a.end,begin,end){hit=0;}
   else if cached && item.ty==b.ty && equal(source,r,b.start,b.end,begin,end){hit=1;}
   if r.status!=0{return static_ag_core::Checked {status:r.status,meter:r.meter};}
   if hit>=0 {let slot=if hit==0 {a} else {b};if !replay(r,1,slot.p1) || !replay(r,2,slot.p2){return static_ag_core::Checked {status:r.status,meter:r.meter};}}
   else {
    var own:u8[>..]=[];if item.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
    if !reads(r,(end-begin) as u64){return static_ag_core::Checked {status:r.status,meter:r.meter};}own.append(source[begin..end]);own.push('\n');
    let before=r.meter.phase_semantic[0];var child=static_b_parse::parse(own,r.meter);r.meter=child.meter;
    if child.status!=0{return static_ag_core::Checked {status:child.status,meter:r.meter};}let p1=r.meter.phase_semantic[0]-before;let vbefore=r.meter.phase_semantic[1];
    let check=static_b_verify::verify(own,child.tree,r.meter);r.meter=check.meter;
    if !check.ok {return static_ag_core::Checked {status:if check.limited {4} else if check.work_status==5 {5} else if check.work_status==6 {6} else {1},meter:r.meter};}
    let slot=Slot {start:begin,end:end,ty:item.ty,p1:p1,p2:r.meter.phase_semantic[1]-vbefore};
    if next==0 {a=slot;next=1;}else {b=slot;next=0;}
   }
   if col+1<p.width && !word(source,r,5,","){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
  }
  if !word(source,r,5,")"){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
  if row+1<p.rows && !word(source,r,5,","){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
 }
 if p.is_array && !word(source,r,5,"]"){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
 while r.status==0 && r.t.kind==6 {advance(source,r);}
 return static_ag_core::Checked {status:if r.status!=0 {r.status} else if r.t.kind==0 {0} else {1},meter:r.meter};
}
