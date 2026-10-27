// Independent bounded decoder for the provisional registry. Its expected
// table is separate from the producer; semantic coverage still needs audit.
namespace abi_overload_verify;
import abi_overload_expected;
struct Reader {at:i64=0,end:i64=0,bad:bool=false}
fn word(s:u8[:],r:Reader&)->u32 {
 if r.bad || r.at<0 || r.end<r.at || r.end>s.len || r.end-r.at<4 {r.bad=true;return 0;}
 let p=r.at;r.at+=4;return s[p]|((s[p+1] as u32)<<8)|((s[p+2] as u32)<<16)|((s[p+3] as u32)<<24);
}
fn expect(s:u8[:],r:Reader&,wanted:u8[:])->bool {
 let n=word(s,r) as i64;if r.bad || n>4096 || n>r.end-r.at || n!=wanted.len {r.bad=true;return false;}
 let at=r.at;r.at+=n;return s[at..r.at]==wanted;
}
fn verify(s:u8[:])->bool {
 if s.len<12 || s.len>131072 || s[..8]!="K1OPS001" {return false;}
 var r=Reader {at:8,end:s.len};if word(s,r)!=80 {return false;}
 for i in 80 {
  if word(s,r)!=(i+1) as u32 || !expect(s,r,"PRIVATE-OVERLOAD-CANDIDATE1") ||
   !expect(s,r,abi_overload_expected::name(i)) || !expect(s,r,abi_overload_expected::operands(i)) ||
   !expect(s,r,abi_overload_expected::result(i)) || !expect(s,r,abi_overload_expected::evidence(i)) ||
   !expect(s,r,abi_overload_expected::behavior(i)) || !expect(s,r,abi_overload_expected::transition(i)) ||
   !expect(s,r,abi_overload_expected::failure(i)) || !expect(s,r,"target-and-implementation-unqualified") ||
   word(s,r)!=0 || r.bad {return false;}
 }
 return !r.bad && r.at==r.end;
}
