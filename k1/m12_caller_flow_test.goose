import std;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var found=false;while i<s.len {if !found && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;found=true;}else {out.push(s[i]);i+=1;}}assert(found);return out;}
import os; import m12_internal_emit; import m12_internal_target;
import m12_caller_flow_build; import m12_caller_flow_verify;
fn main(){let k=kernel();let a=m12_adapter_schema::source();var p,status=m12_adapter_build::build(k,a);assert(status==0);var src:u8[>..]=[];src.append(k);src.append(a);let b=m12_internal_emit::emit(p,src);assert(b.len>0 && write_file("private-invoke.wasm",b));
 var r=m12_caller_flow_build::build(p,src,b);assert(r.status==0 && m12_caller_flow_verify::verify(p,src,b,r.proof));
 for i in 12 {for f in 7 {let old=r.proof.steps[i];if f==0 {r.proof.steps[i].kind+=1;}else if f==1 {r.proof.steps[i].site+=1;}else if f==2 {r.proof.steps[i].callee+=1;}else if f==3 {r.proof.steps[i].depth+=1;}else if f==4 {r.proof.steps[i].parent+=1;}else if f==5 {r.proof.steps[i].before+=1;}else {r.proof.steps[i].after+=1;}assert(!m12_caller_flow_verify::verify(p,src,b,r.proof));r.proof.steps[i]=old;}}
 for f in 5 {if f==0 {r.proof.padding_load+=1;}else if f==1 {r.proof.input_load+=1;}else if f==2 {r.proof.input_store+=1;}else if f==3 {r.proof.output_load+=1;}else {r.proof.output_store+=1;}assert(!m12_caller_flow_verify::verify(p,src,b,r.proof));if f==0 {r.proof.padding_load-=1;}else if f==1 {r.proof.input_load-=1;}else if f==2 {r.proof.input_store-=1;}else if f==3 {r.proof.output_load-=1;}else {r.proof.output_store-=1;}}
 var forged=copy(b);forged[forged.len-1]^=1;assert(!m12_caller_flow_verify::verify(p,src,forged,r.proof));assert(!m12_caller_flow_verify::verify(p,"wrong",b,r.proof));
 let alt=replace(k,"source[i].x + source[i].vx * dt","source[i].vx + source[i].x * dt");var p2,code=m12_adapter_build::build(alt,a);assert(code==0);var src2:u8[>..]=[];src2.append(alt);src2.append(a);let b2=m12_internal_emit::emit(p2,src2);assert(b2.len>0);assert(!m12_caller_flow_verify::verify(p2,src2,b2,r.proof));var r2=m12_caller_flow_build::build(p2,src2,b2);assert(r2.status==0 && m12_caller_flow_verify::verify(p2,src2,b2,r2.proof));
 print("source/target-bound caller operation provenance passed");}
