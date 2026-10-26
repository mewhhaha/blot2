// Independent token recognizer for the narrow private qualified call. It does
// not call the producer parser and compares every stored source span.
namespace link_consumer_check;
import lexer;
import validate;
import link_consumer;
fn verify(s:u8[:],call:link_consumer::Call) -> bool {
 if call.status!=0 {return false;}
 let expected=["let","",":","U32","->","U32","=","fn","","=>","return","",".","","(","",")"];
 var state=lexer::init(s);var param_start:i64=0;var param_end:i64=0;var fn_start:i64=0;var fn_end:i64=0;
 for word,i in expected {
  let t=lexer::next(s,state);if t.kind==0 || t.kind>=6 || t.start<0 || t.end<=t.start || t.end>s.len {return false;}
  let bytes=s[t.start..t.end];
  if i==1 || i==8 || i==11 || i==13 || i==15 {
   if t.kind!=1 || !validate::name_valid(bytes) {return false;}
   if i==1 {if t.start!=call.name_start || t.end!=call.name_end {return false;}fn_start=t.start;fn_end=t.end;}
   if i==8 {if t.start!=call.param_start || t.end!=call.param_end {return false;}param_start=t.start;param_end=t.end;}
   if i==11 && ((t.start!=call.alias_start || t.end!=call.alias_end) || bytes==s[param_start..param_end] || bytes==s[fn_start..fn_end]) {return false;}
   if i==13 && (t.start!=call.target_start || t.end!=call.target_end) {return false;}
   if i==15 && bytes!=s[param_start..param_end] {return false;}
  } else if bytes!=word {return false;}
 }
 var tail=lexer::next(s,state);while tail.kind==6 {tail=lexer::next(s,state);}
 return tail.kind==0;
}
