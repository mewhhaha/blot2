// Restricted structural tuple schemas; not a canonical complete M10 policy.
namespace abi_product_schema;
import lexer;
import public_artifact;
fn same(s:u8[:],t:lexer::Token,text:u8[:])->bool {return t.start>=0 && t.end>=t.start && t.end<=s.len && s[t.start..t.end]==text;}
fn count(s:u8[:])->i64 {
 if s.len==0 || s.len>256{return 0;}
 for c in s {if c=='\n' || c=='\r' || c=='\t' || c=='/' {return 0;}}
 var l=lexer::init(s);let open=lexer::next(s,l);if open.kind!=5 || !same(s,open,"("){return 0;}
 var n:i64=0;
 loop {let item=lexer::next(s,l);if item.kind!=1 || !same(s,item,"U32"){return 0;}n+=1;if n>16{return 0;}
  let delimiter=lexer::next(s,l);if delimiter.kind!=5{return 0;}
  if same(s,delimiter,")"){break;}if !same(s,delimiter,","){return 0;}}
 let end=lexer::next(s,l);if end.kind!=0 || n<2{return 0;}return n;
}
fn canonical(s:u8[:])->u8[] {
 let n=count(s);if n==0{return [];}
 var out:u8[>..]=[];out.append("K1TUP001");for x in [1 as u32,n as u32,(n*4) as u32,4 as u32,3 as u32] {public_artifact::put32(out,x);}for i in n {public_artifact::put32(out,2);}return out;
}
