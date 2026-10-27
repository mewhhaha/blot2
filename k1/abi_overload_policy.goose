// Private revision: canonical base inventory + proposed per-overload schemas.
// No digest from this provisional policy is the qualified M10 ABI hash.
namespace abi_overload_policy;
import abi_profile_build;
import abi_profile_verify;
import abi_overload_build;
import abi_overload_verify;
import public_artifact;
struct Reader {at:i64=0,end:i64=0,bad:bool=false}
fn word(s:u8[:],r:Reader&)->u32 {
 if r.bad || r.at<0 || r.end<r.at || r.end>s.len || r.end-r.at<4 {r.bad=true;return 0;}
 let p=r.at;r.at+=4;return s[p]|((s[p+1] as u32)<<8)|((s[p+2] as u32)<<16)|((s[p+3] as u32)<<24);
}
fn blob(s:u8[:],r:Reader&,max:i64)->i64,i64 {
 let n=word(s,r) as i64;if r.bad || n>max || n>r.end-r.at {r.bad=true;return 0,0;}
 let a=r.at;r.at+=n;return a,r.at;
}
fn canonical()->u8[] {
 let profile=abi_profile_build::canonical();let registry=abi_overload_build::canonical();
 if !abi_profile_verify::verify(profile) || !abi_overload_verify::verify(registry) {return [];}
 var out:u8[>..]=[];out.append("K1POL002");public_artifact::putstr(out,profile);public_artifact::putstr(out,registry);return out;
}
fn verify(s:u8[:])->bool {
 if s.len<16 || s.len>147456 || s[..8]!="K1POL002" {return false;}
 var r=Reader {at:8,end:s.len};let a,b=blob(s,r,16384);let c,d=blob(s,r,131072);
 if r.bad || r.at!=r.end || a==b || c==d {return false;}
 return abi_profile_verify::verify(s[a..b]) && abi_overload_verify::verify(s[c..d]);
}
