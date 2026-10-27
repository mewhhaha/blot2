// Separate byte parser and record decoder. Only exact U32 tuple syntax with
// inline spaces is recognized; it derives semantics from the trusted type
// request, not the producer's length, flag, schema ID or status.
namespace abi_product_check;
fn spaces(s:u8[:],p:i64)->i64 {var i=p;while i<s.len && s[i]==' ' {i+=1;}return i;}
fn read(s:u8[:],p:i64)->u32 {return (s[p] as u32)|((s[p+1] as u32)<<8)|((s[p+2] as u32)<<16)|((s[p+3] as u32)<<24);}
fn count(s:u8[:])->i64 {
 if s.len==0 || s.len>256{return 0;}var p=spaces(s,0);if p>=s.len || s[p]!='(' {return 0;}p+=1;var n:i64=0;
 loop {p=spaces(s,p);if p>s.len-3 || s[p..p+3]!="U32" {return 0;}p+=3;n+=1;if n>16{return 0;}
  p=spaces(s,p);if p>=s.len{return 0;}let c=s[p];p+=1;if c==')'{break;}if c!=','{return 0;}}
 return if spaces(s,p)==s.len && n>=2 {n} else {0};
}
fn verify(s:u8[:],schema:u8[:])->bool {
 let n=count(s);if n==0 || schema.len!=28+4*n || schema[..8]!="K1TUP001" {return false;}
 if read(schema,8)!=1 || read(schema,12)!=n || read(schema,16)!=4*n || read(schema,20)!=4 || read(schema,24)!=3 {return false;}
 for i in n {if read(schema,28+4*i)!=2{return false;}}return true;
}
