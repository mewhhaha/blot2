import abi_overload_build;
import abi_overload_verify;
import abi_overload_policy;
import abi_overload_manifest;
import abi_overload_gaps;
import abi_overload_catalog;
import m12_adapter_schema;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let registry=abi_overload_build::canonical();assert(registry.len>0 && abi_overload_verify::verify(registry));
 assert(abi_overload_gaps::count()==8 && !abi_overload_gaps::publicly_eligible(registry));
 for i in abi_overload_gaps::count() {assert(abi_overload_gaps::reason(i).len>0);}
 assert(abi_overload_catalog::count()==80);
 for i in abi_overload_catalog::count() {
  assert(abi_overload_catalog::name(i).len>0 && abi_overload_catalog::operands(i).len>0 && abi_overload_catalog::result(i).len>0 &&
   abi_overload_catalog::evidence(i).len>0 && abi_overload_catalog::behavior(i).len>0 && abi_overload_catalog::transition(i).len>0 &&
   abi_overload_catalog::failure(i).len>0);
  for j in i {assert(abi_overload_catalog::name(i)!=abi_overload_catalog::name(j));}
 }
 // Family-presence control; it does not prove all specializations exist.
 for wanted in ["region.reserve","region.try_alloc","env.try_alloc","dest.split","builder.begin_append","builder.begin_resize",
  "builder.append","builder.try_append","builder.set","builder.truncate","builder.freeze","builder.discard","view.read","view.try_read",
  "view.slice","index.try_make","space.end","region.reset","region.close","owned.begin","owned.seal","owned.abort","owned.open","owned.close","fn.place"] {
  var found=false;for i in abi_overload_catalog::count() {if abi_overload_catalog::name(i)==wanted {found=true;}}
  assert(found);
 }
 for i in registry.len {var changed:u8[>..]=[];changed.append(registry);changed[i]^=1;assert(!abi_overload_verify::verify(changed));}
 for i in registry.len {assert(!abi_overload_verify::verify(registry[..i]));}
 var extended:u8[>..]=[];extended.append(registry);extended.push(0);assert(!abi_overload_verify::verify(extended));
 let policy=abi_overload_policy::canonical();assert(policy.len>registry.len && abi_overload_policy::verify(policy));
 let kernel=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");let adapter=m12_adapter_schema::source();
 let envelope=abi_overload_manifest::make(kernel,adapter,"pkg","project.blot");
 assert(envelope.len>policy.len && abi_overload_manifest::verify(envelope,kernel,adapter,"pkg","project.blot"));
 for i in envelope.len {if i%23==0 {var changed:u8[>..]=[];changed.append(envelope);changed[i]^=1;
  assert(!abi_overload_manifest::verify(changed,kernel,adapter,"pkg","project.blot"));}}
 for i in envelope.len {assert(!abi_overload_manifest::verify(envelope[..i],kernel,adapter,"pkg","project.blot"));}
 let other=source("source[i].vx","source[i].x");assert(!abi_overload_manifest::verify(envelope,other,adapter,"pkg","project.blot"));
 assert(!abi_overload_manifest::verify(envelope,kernel,adapter,"other","project.blot"));
 print("private provisional per-overload schemas and policy binding passed");
}
