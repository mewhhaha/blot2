// Independent decoder; exact expected builtin is supplied by the trusted
// compiler request, never inferred from a numeric schema ID or digest alone.
namespace abi_primitive_check;
fn read(s:u8[:],p:i64)->u32 {return (s[p] as u32)|((s[p+1] as u32)<<8)|((s[p+2] as u32)<<16)|((s[p+3] as u32)<<24);}
fn verify(s:u8[:],code:u32)->bool {
 if s.len!=40 || s[..8]!="K1PRIM01" || code<1 || code>4{return false;}
 let unit=code==1;let vals:u32[8]=[1,code,if unit {0} else {4},if unit {1} else {4},if unit {7} else {3},code-1,if unit {0} else if code==3 {2} else {1},1];
 for i in 8 {if read(s,8+4*i)!=vals[i] {return false;}}return true;
}
