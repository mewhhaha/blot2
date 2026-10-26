import particle_source_core;
import particle_lower_parse;
import particle_lower_verify;
fn main() {
let source="pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";
let ctx=particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,dt:7,dt_version:8,builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,result:16,result_version:17,result_domain:18};
var original,status=particle_lower_parse::parse(source,ctx);assert(status==0 && particle_lower_verify::verify(original,source,ctx));
var bytes:u8[>..]=[];bytes.append(source);let repl:u8[8]=[0,10,32,35,48,120,121,255];var accepted=0;var rejected=0;
for i in bytes.len {let old=bytes[i];for c in repl {bytes[i]=c;var p,st=particle_lower_parse::parse(bytes,ctx);if st==0 {accepted+=1;assert(particle_lower_verify::verify(p,bytes,ctx));}else {rejected+=1;}if c!=old {assert(!particle_lower_verify::verify(original,bytes,ctx));}}bytes[i]=old;}
assert(accepted>0 && rejected>0);print("particle lexical mutation controls passed: ",accepted," accepted and ",rejected," rejected");
}