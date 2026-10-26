import std;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var found=false;while i<s.len {if !found && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;found=true;}else {out.push(s[i]);i+=1;}}assert(found);return out;}
import os; import m12_one_emit; import m12_one_target;
fn main(){let original=kernel();let first=replace(original,"source[i].x + source[i].vx * dt","source[i].vx");let k=replace(first,"source[i].y + source[i].vy * dt","source[i].x");let a=m12_adapter_schema::source();var p,status=m12_adapter_build::build(k,a);assert(status==0);var src:u8[>..]=[];src.append(k);src.append(a);let bytes=m12_one_emit::emit(p,src);assert(bytes.len>0 && m12_one_target::verify(p,src,bytes) && write_file("variant.wasm",bytes));print("one-module alternate source worker passed");}
