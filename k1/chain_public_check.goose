// Independent direct recognition of the original public wrapper. This never
// consumes the producer's synthetic identity source or treats it as a body.
namespace chain_public_check;
import lexer;
import validate;
import public_frontend;
fn verify(s:u8[:],name_start:i64,name_end:i64,param_start:i64,param_end:i64,
 alias_start:i64,alias_end:i64,target_start:i64,target_end:i64,depth:u32,frame:u32)->bool {
 let expected=["pub","let","",":","U32","->","U32","!","{","}","resources","{","depth",":","",",","frame",":","","}","=","fn","","=>","return","",".","","(","",")"];
 var state=lexer::init(s);var pn:i64=-1;var pe:i64=-1;var fnn:i64=-1;var fne:i64=-1;
 for word,i in expected {
  let t=lexer::next(s,state);if t.kind==0 || t.kind>=6 || t.start<0 || t.end<=t.start || t.end>s.len {return false;}
  let bytes=s[t.start..t.end];
  if i==2 || i==22 || i==25 || i==27 || i==29 {
   if t.kind!=1 || !validate::name_valid(bytes) {return false;}
   if i==2 {if t.start!=name_start || t.end!=name_end {return false;}fnn=t.start;fne=t.end;}
   if i==22 {if t.start!=param_start || t.end!=param_end {return false;}pn=t.start;pe=t.end;}
   if i==25 {if t.start!=alias_start || t.end!=alias_end || bytes==s[pn..pe] || bytes==s[fnn..fne] {return false;}}
   if i==27 && (t.start!=target_start || t.end!=target_end) {return false;}
   if i==29 && bytes!=s[pn..pe] {return false;}
  }else if i==14 || i==18 {
   let value,ok=public_frontend::number(s,t);if !ok || (i==14 && value!=depth) || (i==18 && value!=frame) {return false;}
  }else if bytes!=word {return false;}
 }
 var tail=lexer::next(s,state);while tail.kind==6 {tail=lexer::next(s,state);}return tail.kind==0 && depth>=1 && depth<=128;
}
