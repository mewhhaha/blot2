// Bounded extraction/decoding helpers, never authority on their own.
namespace m12_caller_flow_bytes;
import i08_same_target;
struct Slice {start:i64=0,end:i64=0,ok:bool=false}
fn body(target:u8[:])->Slice {
 var p:i64=8;for id in [1,3,5,7] {let s=i08_same_target::section(target,p,id as u8);if !s.ok {return Slice {};}p=s.end;}
 let code=i08_same_target::section(target,p,10);if !code.ok || code.end!=target.len{return Slice {};}
 let n=i08_same_target::read_leb(target,code.payload,code.end);if !n.ok || n.value!=23{return Slice {};}
 var at=n.next;for i in 23 {let len=i08_same_target::read_leb(target,at,code.end);if !len.ok || len.value>code.end-len.next{return Slice {};}
  let end=len.next+len.value;if i==22 {return Slice {start:len.next,end:end,ok:end==code.end};}at=end;}
 return Slice {};
}
// Signed LEB can use a sign-extended fifth byte, unlike unsigned indices.
fn skip_signed(code:u8[:],p:i64)->i64 {var at=p;for _ in 5 {if at>=code.len{return -1;}let b=code[at];at+=1;if (b&128)==0{return at;}}return -1;}
fn unsigned_end(code:u8[:],p:i64)->i64 {let q=i08_same_target::read_leb(code,p,code.len);return if q.ok {q.next} else {-1};}
