import std;
import static_compound_build;
import static_compound_verify;
import static_compound_eval;
fn word(b:u8[:],p:i64)->u32 {return b[p] | ((b[p+1] as u32)<<8) | ((b[p+2] as u32)<<16) | ((b[p+3] as u32)<<24);}
fn main() {
 for i in 300 {
  let mask=(i*13)%256;let v=(i*47)%1234;let w=(i*91)%1201;
  var src:u8[>..]=[];
  format(src,"let f: U32 -> U32 = fn x => return g(x)\nlet g: U32 -> U32 = fn x => return x & ",mask,"\nstatic let a = (f(",v,"), f(",w,"))\n");
  var p=static_compound_build::build(src);assert(p.status==0 && static_compound_verify::verify(src,p.program));
  let result=static_compound_eval::evaluate(src,p.program);assert(result.status==0 && result.depth==2 && result.bytes==8);
  assert(word(result.data,0)==((v as u32)&(mask as u32)) && word(result.data,4)==((w as u32)&(mask as u32)));
  for j in p.program.calls.len {
   var bad=copy(p.program);bad.calls[j].argument ^= 1;assert(!static_compound_verify::verify(src,bad));
   var bad2=copy(p.program);bad2.calls[j].target=9223372036854775807;assert(!static_compound_verify::verify(src,bad2));
   var bad3=copy(p.program);bad3.calls[j].start=-1;assert(!static_compound_verify::verify(src,bad3));
  }
 }
 print("private independent compound resolution and operand oracle passed");
}
