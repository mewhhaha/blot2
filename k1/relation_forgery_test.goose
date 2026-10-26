import std;
import unified_guard;
import unified_frontend;
import refinement_guard_verify;
import unified_check;
import unified_wasm;
fn main() {
 let s="let f: U32 -> U32 = fn x => do:\n  let a = x\n  let b = U32.wrapping_add(x, 1)\n  let c = U32.wrapping_add(x, 2)\n  if a <= b && b <= c && c < 4294967295:\n    return x + 1\n  else:\n    return x\n";
 var p=unified_frontend::parse(s);assert(p.status==0 && unified_check::verify(s,p.program));
 let e=unified_guard::check(s,p.program);assert(e.status==0 && e.evidence.len==1 && e.evidence[0].path_count==2);
 assert(refinement_guard_verify::verify_evidence(s,p.program,e.evidence));
 for field in 8 {var fake:unified_guard::Evidence[>..]=[];fake.append(e.evidence);
 if field==0 {fake[0].guard_id=-1;} else if field==1 {fake[0].guard_true=!fake[0].guard_true;} else if field==2 {fake[0].subject=999999;}
 else if field==3 {fake[0].reference=999999;} else if field==4 {fake[0].one=999999;} else if field==5 {fake[0].addition=999999;}
 else if field==6 {fake[0].path_count=0;} else {fake[0].path_count=17;}
 assert(!refinement_guard_verify::verify_evidence(s,p.program,fake));}
 for i in 16 {var fake:unified_guard::Evidence[>..]=[];fake.append(e.evidence);fake[0].path_guard[i]=999999;assert(!refinement_guard_verify::verify_evidence(s,p.program,fake));
 fake[0]=e.evidence[0];fake[0].path_true[i]=!fake[0].path_true[i];assert(!refinement_guard_verify::verify_evidence(s,p.program,fake));}
 for i in p.program.nodes.len {for f in 8 {let old=p.program.nodes[i];
 if f==0 {p.program.nodes[i].tag=999999;} else if f==1 {p.program.nodes[i].start=-1;} else if f==2 {p.program.nodes[i].end=999999;}
 else if f==3 {p.program.nodes[i].a=999999;} else if f==4 {p.program.nodes[i].b=999999;} else if f==5 {p.program.nodes[i].c=999999;}
 else if f==6 {p.program.nodes[i].literal=if old.literal==0 {1} else {0};} else {p.program.nodes[i].ty=999999;}
 assert(!refinement_guard_verify::verify_evidence(s,p.program,e.evidence) && !unified_check::verify(s,p.program) && unified_wasm::emit(s,p.program).len==0);p.program.nodes[i]=old;
 }}
 for i in p.program.bindings.len {let old=p.program.bindings[i];p.program.bindings[i].start=-1;assert(!refinement_guard_verify::verify_evidence(s,p.program,e.evidence));p.program.bindings[i]=old;
 p.program.bindings[i].end=999999;assert(!refinement_guard_verify::verify_evidence(s,p.program,e.evidence));p.program.bindings[i]=old;}
 for i in p.program.source.len {let old=p.program.source[i];p.program.source[i]=if old=='?' {'!'} else {'?'};assert(!refinement_guard_verify::verify_evidence(s,p.program,e.evidence));p.program.source[i]=old;}
 print("source, node, alias, path and origin forgeries rejected");
}
