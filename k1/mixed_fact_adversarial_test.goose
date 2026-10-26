import mixed_parse;
import mixed_fact_core;
import mixed_fact_build;
import mixed_fact_verify;
fn main(){
 let src="fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    if a < 4294967295:\n      next (a + 1)\n    else:\n      stop (a)\n  return sum\n";
 var tree,status=mixed_parse::parse(src);assert(status==0);let p=mixed_fact_build::build(tree);assert(p.status==0 && p.events.len==1 && mixed_fact_verify::verify(tree,src,p.events));
 for field in 10 {var e:mixed_fact_core::Evidence[>..]=[];e.append(p.events);if field==0 {e[0].guard_id=-1;}else if field==1 {e[0].truth=!e[0].truth;}else if field==2 {e[0].subject=9999;}else if field==3 {e[0].reference=-1;}else if field==4 {e[0].one=-1;}else if field==5 {e[0].addition=9999;}else if field==6 {e[0].count=-1;}else if field==7 {e[0].count=17;}else if field==8 {e[0].guards[15]=5;}else {e[0].edges[15]=true;}assert(!mixed_fact_verify::verify(tree,src,e));}
 assert(!mixed_fact_verify::verify(tree,"wrong",p.events));
 let unsafe="fn x => do:\n  if x < 4294967295:\n    let sum = for i in 0..2 carry (a=x) do:\n      next (a + 1)\n    return sum\n  else:\n    return x\n";
 var bad,badstatus=mixed_parse::parse(unsafe);assert(badstatus==0);let b=mixed_fact_build::build(bad);assert(b.status!=0 && !mixed_fact_verify::verify(bad,unsafe,b.events));
 let ill="fn x => do:\n  if #False < #True:\n    return x + 1\n  else:\n    return x\n";
 var invalid,st=mixed_parse::parse(ill);assert(st==0);let q=mixed_fact_build::build(invalid);assert(!mixed_fact_verify::verify(invalid,ill,q.events));
 print("independent mixed proof evidence passed");
}
