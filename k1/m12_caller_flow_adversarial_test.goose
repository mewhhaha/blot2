import m12_adapter_schema;
import m12_adapter_build;
import m12_internal_emit;
import m12_caller_flow_build;
import m12_caller_flow_verify;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}

fn main() {
 let k=kernel();let adapter=m12_adapter_schema::source();var p,status=m12_adapter_build::build(k,adapter);assert(status==0);
 var source:u8[>..]=[];source.append(k);source.append(adapter);let target=m12_internal_emit::emit(p,source);assert(target.len>0);
 var built=m12_caller_flow_build::build(p,source,target);assert(built.status==0 && m12_caller_flow_verify::verify(p,source,target,built.proof));
 for i in 12 {for field in 5 {for value in [-1,9223372036854775807] {
  var forged=copy(built.proof);
  if field==0 {forged.steps[i].kind=value;}else if field==1 {forged.steps[i].site=value;}else if field==2 {forged.steps[i].callee=value;}
  else if field==3 {forged.steps[i].depth=value;}else {forged.steps[i].parent=value;}
  if field!=4 || value!=built.proof.steps[i].parent {assert(!m12_caller_flow_verify::verify(p,source,target,forged));}
 }}}
 for i in 12 {var a=copy(built.proof);a.steps[i].before=4294967295;assert(!m12_caller_flow_verify::verify(p,source,target,a));
  var b=copy(built.proof);b.steps[i].after=4294967295;assert(!m12_caller_flow_verify::verify(p,source,target,b));}
 var reverse=copy(built.proof);let t=reverse.steps[8];reverse.steps[8]=reverse.steps[9];reverse.steps[9]=t;
 assert(!m12_caller_flow_verify::verify(p,source,target,reverse));
 for n in target.len {assert(!m12_caller_flow_verify::verify(p,source,target[..n],built.proof));}
 print("private caller proof forged extremes and truncations rejected");
}
