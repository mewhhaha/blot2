import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_fact_build;
import short_fact_verify;
import mixed_fact_core;
fn main(){
 let depths:i64[]=[1,30,60,100,120];
 for variant in 3 {for count in depths {var s:u8[>..]=[];s.append("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return ");
  for _ in count {if variant==0 {s.append("#True && ");}else if variant==1 {s.append("#False || ");}else {s.append("(x < 4294967295 && #True) && ");}}
  s.append("x < 4294967295 && (x + 1) < 5\n");var p=short_frontend::parse(s);
  if p.status!=0 {print("bad depth ",variant," ",count," status ",p.status);}assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && write_file(str("iter-",variant,"-",count,".wasm"),b));
  for node,i in p.program.tree.nodes {if node.tag==23 || node.tag==24 {let original=node;p.program.tree.nodes[i].a=i+1;let result=short_fact_build::build(p.program.tree);assert(result.status!=0);let none:mixed_fact_core::Evidence[0]=[];assert(!short_fact_verify::verify(p.program.tree,p.program.tree.source,none,1,2));p.program.tree.nodes[i]=original;break;}}
 }}
 print("deep mixed predecessor chains and forged cycles passed");
}
