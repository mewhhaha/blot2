import joined_public_frontend;
import joined_public_wasm;
import joined_driver_gate;
fn main() {
 let s="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n";
 var p=joined_public_frontend::parse(s);assert(p.status==0);
 let target=joined_public_wasm::emit(s,p.program);assert(joined_driver_gate::matches(s,p.program,target));
 for i in s.len {var b=copy(p.program);b.source[i]^=1;assert(!joined_driver_gate::matches(s,b,target));var alt=copy(b.source);assert(!joined_driver_gate::matches(alt,b,target));}
 for f in 7 {var b=copy(p.program);if f==0 {b.head.ok=false;} else if f==1 {b.head.let_start= -1;} else if f==2 {b.head.effect_start= -1;} else if f==3 {b.head.resources_end=9223372036854775807;} else if f==4 {b.head.depth+=1;} else if f==5 {b.head.frame+=1;} else {b.body.variant+=1;}assert(!joined_driver_gate::matches(s,b,target));}
 for n in target.len {assert(!joined_driver_gate::matches(s,p.program,target[..n]));}
 var suffix:u8[>..]=[];suffix.append(target);suffix.push(0);assert(!joined_driver_gate::matches(s,p.program,suffix));
 for i in p.program.body.scalar.nodes.len {for f in 8 {var b=copy(p.program);if f==0 {b.body.scalar.nodes[i].tag+=1;} else if f==1 {b.body.scalar.nodes[i].start= -1;} else if f==2 {b.body.scalar.nodes[i].end=9223372036854775807;} else if f==3 {b.body.scalar.nodes[i].a+=1;} else if f==4 {b.body.scalar.nodes[i].b+=1;} else if f==5 {b.body.scalar.nodes[i].c+=1;} else if f==6 {b.body.scalar.nodes[i].literal+=1;} else {b.body.scalar.nodes[i].ty+=1;}assert(!joined_driver_gate::matches(s,b,target));}}
 print("independent source/header/body/target mutation controls passed");
}
