import std;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var found=false;while i<s.len {if !found && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;found=true;}else {out.push(s[i]);i+=1;}}assert(found);return out;}
fn main() {let k=kernel();let a=m12_adapter_schema::source();var p,status=m12_adapter_build::build(k,a);assert(status==0);var module:u8[>..]=[];module.append(k);module.append(a);assert(m12_adapter_verify::verify(p,module) && !m12_adapter_verify::public_eligible(p,module));
 for i in p.events.len {let old=p.events[i];p.events[i].kind+=1;assert(!m12_adapter_verify::verify(p,module));p.events[i]=old;p.events[i].site+=1;assert(!m12_adapter_verify::verify(p,module));p.events[i]=old;}
 let node=p.linked.tree.nodes[0];p.linked.tree.nodes[0].a+=1;assert(!m12_adapter_verify::verify(p,module));p.linked.tree.nodes[0]=node;
 let t=p.transition.steps[0];p.transition.steps[0].nat+=1;assert(!m12_adapter_verify::verify(p,module));p.transition.steps[0]=t;
 for changes in [["output: Dest[","output: View["],["write r}","write r, host}"],["write r}","write r, reserve}"],["begin_append(dst)","begin_append(input)"],["begin_append(dst)","begin_append(started)"],["project@[r,r,n,c,d]","project@[r,r,c,n,d]"],["pack [n,e]","pack [c,e]"],["pack [n,e]","pack [n,d]"],["#Ok(wrapped)","#Ok(input)"],["depth: 3","depth: 2"],["return #Ok(wrapped)","return #Err(())"],["project@[r,r,n,c,d](input,step,started)","project@[r,r,n,c,d](input,step,dst)"],["let result = project", "let reused = dst\n  let result = project"],["let wrapped = open result", "let wrapped = open input"],["read r, write r", "write r"]] {
  let altered=replace(a,changes[0],changes[1]);let _,code=m12_adapter_build::build(k,altered);assert(code!=0);var mod:u8[>..]=[];mod.append(k);mod.append(altered);assert(!m12_adapter_verify::verify(p,mod));
 }
 let bad_kernel=replace(k,"read r, write s", "read r, write s, host");let _,bad_code=m12_adapter_build::build(bad_kernel,a);assert(bad_code!=0);
 let _,cut=m12_adapter_build::build(k[..k.len-1],a);assert(cut!=0);
 var altered:u8[>..]=[];altered.append(module);for i in altered.len {let old=altered[i];altered[i]=if old=='?' {'!'} else {'?'};assert(!m12_adapter_verify::verify(p,altered));altered[i]=old;}
 print("closed record/Dest/Result adapter source proof passed; M12 gate remains closed");}
