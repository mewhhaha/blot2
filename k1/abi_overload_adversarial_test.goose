import std;
import abi_overload_build;
import abi_overload_verify;
import abi_overload_gaps;
import abi_overload_policy;
fn get(s:u8[:],i:i64)->i64{return (s[i] as i64)|((s[i+1] as i64)<<8)|((s[i+2] as i64)<<16)|((s[i+3] as i64)<<24);}
fn main() {
 let original=abi_overload_build::canonical();assert(abi_overload_verify::verify(original) && !abi_overload_gaps::publicly_eligible(original));var at:i64=12;
 for row in 80 {assert(get(original,at)==row+1);at+=4;for field in 9 {let length=get(original,at);assert(length>=0 && length<=4096);at+=4+length;}
  assert(at+4<=original.len && get(original,at)==0);var altered:u8[>..]=[];altered.append(original);altered[at]=1;
  assert(!abi_overload_verify::verify(altered) && !abi_overload_gaps::publicly_eligible(altered));at+=4;
 }assert(at==original.len);
 let four:u8[4]=[1,2,3,4];for v in [-1,5,999999,9223372036854775807] {
  var a=abi_overload_verify::Reader {at:v,end:4};let _=abi_overload_verify::word(four,a);assert(a.bad);
  var b=abi_overload_policy::Reader {at:v,end:4};let _=abi_overload_policy::word(four,b);assert(b.bad);
 }
 assert(!abi_overload_gaps::publicly_eligible(""));print("all 80 provisional flags and decoder bounds remain fail-closed");
}
