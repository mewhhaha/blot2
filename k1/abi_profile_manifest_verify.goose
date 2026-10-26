// Private exact ABI-profile/candidate association, not public M12 admission.
// Source/package/module are trusted compiler request inputs, not disk claims.
namespace abi_profile_manifest_verify;
import abi_profile_verify;
import m12_candidate_verify;
import blake3;
struct Reader {at:i64=0,end:i64=0,bad:bool=false}
fn word(s:u8[:],r:Reader&)->u32 {
 if r.bad || r.at<0 || r.end<r.at || r.end>s.len || r.end-r.at<4 {r.bad=true;return 0;}
 let p=r.at;r.at+=4;return s[p]|((s[p+1] as u32)<<8)|((s[p+2] as u32)<<16)|((s[p+3] as u32)<<24);
}
fn blob(s:u8[:],r:Reader&,max:i64)->i64,i64 {
 let n=word(s,r) as i64;if r.bad || n>max || n>r.end-r.at {r.bad=true;return 0,0;}
 let a=r.at;r.at+=n;return a,r.at;
}
fn verify(bytes:u8[:],source:u8[:],adapter:u8[:],package:u8[:],module:u8[:])->bool {
 if bytes.len<12 || bytes.len>147456 || bytes[..8]!="K1AMNF01" {return false;}
 var r=Reader {at:8,end:bytes.len};if word(bytes,r)!=bytes.len{return false;}
 let pa,pb=blob(bytes,r,16384);let ha,hb=blob(bytes,r,32);let ma,mb=blob(bytes,r,131072);
 if r.bad || r.at!=r.end || hb-ha!=32 || pa==pb || ma==mb {return false;}
 let profile=bytes[pa..pb];let digest=bytes[ha..hb];
 if !abi_profile_verify::verify_digest(profile,digest) {return false;}
 return m12_candidate_verify::verify(bytes[ma..mb],source,adapter,package,module,digest);
}
