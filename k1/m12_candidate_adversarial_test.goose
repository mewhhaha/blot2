import std;
import m12_adapter_schema;
import m12_candidate_build;
import m12_candidate_verify;
fn source()->u8[] {var s:u8[>..]=[];s.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n");return s;}
fn get(s:u8[:],i:i64)->i64 {return (s[i] as i64)|((s[i+1] as i64)<<8)|((s[i+2] as i64)<<16)|((s[i+3] as i64)<<24);}
fn main() {
 let src=source();let adapter=m12_adapter_schema::source();let abi:u8[32]=[9;32];let manifest=m12_candidate_build::make(src,adapter,"pkg","project.blot",abi);assert(manifest.len>0 && m12_candidate_verify::verify(manifest,src,adapter,"pkg","project.blot",abi));
 var pos:i64=12;var offsets:i64[11]=[0;11];
 for i in 8 {offsets[i]=pos;pos+=4+get(manifest,pos);assert(pos<=manifest.len);}
 let fields=pos;pos+=23*4;
 for i in 3 {offsets[8+i]=pos;pos+=4+get(manifest,pos);assert(pos<=manifest.len);}assert(pos==manifest.len);
 for at in offsets {for mode in 3 {var data:u8[>..]=[];data.append(manifest);
 if mode==0 {for j in 4 {data[at+j]=255;}}else if mode==1 {data[at]=1;data[at+1]=0;data[at+2]=1;data[at+3]=0;}else {for j in 4 {data[at+j]=0;}}
 if data[..]!=manifest[..] {assert(!m12_candidate_verify::verify(data,src,adapter,"pkg","project.blot",abi));}
 }}
 for i in 16..23 {var data:u8[>..]=[];data.append(manifest);data[fields+4*i]^=1;assert(!m12_candidate_verify::verify(data,src,adapter,"pkg","project.blot",abi));}
 let four:u8[4]=[1,2,3,4];
 for v in [-1,5,999999,9223372036854775807] {var r=m12_candidate_verify::Reader {at:v,end:4};let _=m12_candidate_verify::word(four,r);assert(r.bad);}
 for v in [-1,5,999999,9223372036854775807] {var r=m12_candidate_verify::Reader {at:0,end:v};let _=m12_candidate_verify::word(four,r);assert(r.bad);}
 print("independent manifest length and ineligibility controls passed");
}
