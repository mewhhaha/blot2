import std;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var found=false;while i<s.len {if !found && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;found=true;}else {out.push(s[i]);i+=1;}}assert(found);return out;}
import os; import m12_internal_emit; import m12_internal_target;
fn main(){let k=kernel();let a=m12_adapter_schema::source();var p,status=m12_adapter_build::build(k,a);assert(status==0);var src:u8[>..]=[];src.append(k);src.append(a);let b=m12_internal_emit::emit(p,src);assert(b.len>0 && write_file("private-invoke.wasm",b) && m12_internal_target::verify(p,src,b));assert(!m12_adapter_verify::public_eligible(p,src));
 for i in b.len {var bad=copy(b);bad[i]^=1;assert(!m12_internal_target::verify(p,src,bad));assert(!m12_internal_target::verify(p,src,b[..i]));}
 var extra:u8[>..]=[];extra.append(b);extra.push(0);assert(!m12_internal_target::verify(p,src,extra));
 let other=replace(k,"source[i].x + source[i].vx * dt","source[i].vx + source[i].x * dt");var p2,st=m12_adapter_build::build(other,a);assert(st==0);var src2:u8[>..]=[];src2.append(other);src2.append(a);let b2=m12_internal_emit::emit(p2,src2);assert(b2.len>0 && b2[..]!=b[..]);assert(!m12_internal_target::verify(p,src,b2) && !m12_internal_target::verify(p2,src2,b));
 let save=p.events[0];p.events[0].site+=1;assert(m12_internal_emit::emit(p,src).len==0);p.events[0]=save;assert(m12_internal_emit::emit(p,"wrong").len==0);print("private source-linked in-module caller emitted");}
