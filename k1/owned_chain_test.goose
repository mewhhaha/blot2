import owned_chain;
import source_owned_admit;
import owned_scalar_source;
import owned_scalar_verify;
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var seen=false;while i<s.len {if !seen && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;seen=true;}else {out.push(s[i]);i+=1;}}assert(seen);return out;}
fn no(s:u8[:],a:u8[:],b:u8[:]) {let changed=replace(s,a,b);let r=owned_chain::run(changed);assert(r.status==1 && r.value==0 && r.reserve_error==0);}
fn main(){
 let s="type Scalar[r: Region] = U32\nlet consume: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  owned.close(h)\n  return value\ntype ScalarPayload[r: Region] = U32\nlet main: Unit -> Result[U32,#Reserve(ReserveError) | #Body(#Cancelled)] ! {reserve,release} = fn () => do:\n  let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n    seal(free,4294967295)\n  case built:\n    #Err(e) => return #Err(e)\n    #Ok(h) => return #Ok(consume(h,#True))\n";
 let r=owned_chain::run(s);if r.status!=0 {print("status ",r.status);}assert(r.status==0 && r.value==4294967295);

 let zero=replace(s,"4294967295","0");let z=owned_chain::run(zero);assert(z.status==0 && z.value==0);
 let false_case=replace(s,"#True","#False");let f=owned_chain::run(false_case);assert(f.status==0 && f.value==4294967295);
 let abort=replace(s,"seal(free,4294967295)","abort(free,#Cancelled)");let a=owned_chain::run(abort);assert(a.status==2 && a.value==0 && a.reserve_error==0);
 let too_large=replace(s,"#Cancelled](0)","#Cancelled](3841)");let cap=owned_chain::run(too_large);assert(cap.status==3 && cap.value==0 && cap.reserve_error!=0);
 no(s,"type ScalarPayload[r: Region] = U32","type ScalarPayload[r: Region] = Bool");
 no(s,"type Scalar[r: Region] = U32","type Scalar[r: Region] = Bool");
 no(s,"consume(h,#True)","consume(h,h)");
 no(s,"consume(h,#True)","other(h,#True)");
 no(s,"consume(h,#True)","consume(h,# True)");
 no(s,"#Ok(h) => return #Ok(consume(h,#True))","#Ok(h) => return #Ok(consume(h,#True))\n  owned.close(h)");
 no(s,"owned.close(h)","owned.close(flag)");
 no(s,"return value","return h");
 no(s,"    seal(free,4294967295)","   seal(free,4294967295)");
 no(s,"#Err(e) => return #Err(e)","#Err(e) => return #Ok(e)");
 no(s,"! {reserve,release}","! {reserve}");
 no(s,"let consume:","let other:");
 print("private full-source scalar Owned construction and consumption passed");
}
