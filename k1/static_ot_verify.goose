// Phase 2 independently replays aggregate tokens and each retained scalar
// source/tree without calling the phase-1 parser again. Partial accounting.
namespace static_ot_verify;
import lexer_m;
import work;
import static_m_name;
import static_b_verify;
import static_ag_core;
import static_ag_verify;
import static_order_core;
fn verify(source:u8[:],owned:static_order_core::Owned&,meter:work::Meter)->static_ag_core::Checked {
 let p=owned.product;
 if source.len>16777216 || source.len!=p.source.len || p.rows<1 || p.width<2 || p.width>16 || p.parts.len>100000 ||
  p.rows>100000/p.width || p.parts.len!=p.rows*p.width || owned.scalars.len!=p.parts.len{return static_ag_core::Checked {meter:meter};}
 var initial=meter;for i in source.len {let x=work::source_read(initial,2);if x.status!=0{return static_ag_core::Checked {status:if x.status==5 {5} else {6},meter:initial};}
  if source[i]!=p.source[i]{return static_ag_core::Checked {meter:initial};}}
 var lex=lexer_m::init(source,initial);var r=static_ag_verify::Reader {lex:lex,meter:lex.meter};
 if lex.work_status!=0{return static_ag_core::Checked {status:if lex.work_status==5 {5} else {6},meter:r.meter};}
 static_ag_verify::advance(source,r);
 if !static_ag_verify::word(source,r,1,"static") || !static_ag_verify::word(source,r,1,"let"){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
 let name=r.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>source.len || name.start!=p.name_start || name.end!=p.name_end{return static_ag_core::Checked {meter:r.meter};}
 let named=static_m_name::check(source[name.start..name.end],r.meter);if named.work_status!=0{return static_ag_core::Checked {status:if named.work_status==5 {5} else {6},meter:r.meter};}
 if !named.valid{return static_ag_core::Checked {meter:r.meter};}static_ag_verify::advance(source,r);
 if !static_ag_verify::word(source,r,5,"=") || !p.is_array || !static_ag_verify::word(source,r,5,"#") || !static_ag_verify::word(source,r,5,"[") {return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
 // Charge the next retained tree before entering each loop iteration.
 if owned.scalars.len>0 && !static_ag_verify::visit(r,2){return static_ag_core::Checked {status:r.status,meter:r.meter};}
 for scalar,i in owned.scalars {
  let col=i%p.width;let row=i/p.width;
  if col==0 && !static_ag_verify::word(source,r,5,"("){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
  if !static_ag_verify::visit(r,2) || !static_ag_verify::visit(r,3){return static_ag_core::Checked {status:r.status,meter:r.meter};}
  let part=p.parts[i];let begin=r.t.start;var end=begin;var depth:i64=0;
  while r.status==0 && r.t.kind!=0 {
   if static_ag_verify::is(source,r,r.t,5,"("){depth+=1;}else if static_ag_verify::is(source,r,r.t,5,")"){if depth==0 {break;}depth-=1;}
   else if depth==0 && static_ag_verify::is(source,r,r.t,5,","){break;}end=r.t.end;static_ag_verify::advance(source,r);
  }
  if r.status!=0{return static_ag_core::Checked {status:r.status,meter:r.meter};}
  if !static_ag_verify::visit(r,6){return static_ag_core::Checked {status:r.status,meter:r.meter};}
  if depth!=0 || begin<0 || end<=begin || end>source.len || begin!=part.start || end!=part.end || (part.ty!=1 && part.ty!=2) {return static_ag_core::Checked {meter:r.meter};}
  if !static_ag_verify::visit(r,6){return static_ag_core::Checked {status:r.status,meter:r.meter};}if scalar.ty!=part.ty{return static_ag_core::Checked {meter:r.meter};}
  if row>0 {if !static_ag_verify::visit(r,3) || !static_ag_verify::visit(r,6) || !static_ag_verify::visit(r,6){return static_ag_core::Checked {status:r.status,meter:r.meter};}if part.ty!=p.parts[col].ty{return static_ag_core::Checked {meter:r.meter};}}
  if !static_ag_verify::visit(r,10){return static_ag_core::Checked {status:r.status,meter:r.meter};}
  var own:u8[>..]=[];if part.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
  if !static_ag_verify::reads(r,(end-begin) as u64){return static_ag_core::Checked {status:r.status,meter:r.meter};}
  own.append(source[begin..end]);own.push('\n');let check=static_b_verify::verify(own,scalar,r.meter);r.meter=check.meter;
  if !check.ok{return static_ag_core::Checked {status:if check.limited {4} else if check.work_status==5 {5} else if check.work_status==6 {6} else {1},meter:r.meter};}
  if col+1<p.width {if !static_ag_verify::word(source,r,5,","){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}}
  else {if !static_ag_verify::word(source,r,5,")"){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
   if row+1<p.rows && !static_ag_verify::word(source,r,5,","){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}}
  if i+1<owned.scalars.len && !static_ag_verify::visit(r,2){return static_ag_core::Checked {status:r.status,meter:r.meter};}
 }
 if !static_ag_verify::word(source,r,5,"]"){return static_ag_core::Checked {status:if r.status==0 {1} else {r.status},meter:r.meter};}
 while r.status==0 && r.t.kind==6 {static_ag_verify::advance(source,r);}
 return static_ag_core::Checked {status:if r.status!=0 {r.status} else if r.t.kind==0 {0} else {1},meter:r.meter};
}
