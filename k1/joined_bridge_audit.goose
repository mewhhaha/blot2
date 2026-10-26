import joined_public_frontend;
import joined_public_verify;
import joined_public_wasm;
fn main() {
 let scalar="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n";
 var a=joined_public_frontend::parse(scalar);assert(a.status==0 && a.program.body.variant==1);
 for i in a.program.body.scalar.nodes.len {for f in 8 {var b=copy(a.program);
 if f==0 {b.body.scalar.nodes[i].tag+=1;}else if f==1 {b.body.scalar.nodes[i].start= -1;}else if f==2 {b.body.scalar.nodes[i].end=9223372036854775807;}
 else if f==3 {b.body.scalar.nodes[i].a+=1;}else if f==4 {b.body.scalar.nodes[i].b+=1;}else if f==5 {b.body.scalar.nodes[i].c+=1;}
 else if f==6 {b.body.scalar.nodes[i].literal+=1;}else {b.body.scalar.nodes[i].ty+=1;}
 assert(!joined_public_verify::verify(scalar,b) && joined_public_wasm::emit(scalar,b).len==0);
 }}
 let loop_source="pub let f: U32 -> U32 ! {} resources {depth: 2, frame: 32} = fn x => do:\n  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n";
 var p=joined_public_frontend::parse(loop_source);assert(p.status==0 && p.program.body.variant==2);
 for i in p.program.body.body.nodes.len {for f in 5 {var b=copy(p.program);
 if f==0 {b.body.body.nodes[i].tag+=1;}else if f==1 {b.body.body.nodes[i].start= -1;}else if f==2 {b.body.body.nodes[i].end=9223372036854775807;}
 else if f==3 {b.body.body.nodes[i].a+=1;}else {b.body.body.nodes[i].target+=1;}
 assert(!joined_public_verify::verify(loop_source,b) && joined_public_wasm::emit(loop_source,b).len==0);
 }}
 print("private public-shaped nested scalar/loop forged Core controls passed");
}
