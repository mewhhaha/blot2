import std;import typed_dispatch;import primary_dispatch;
fn main(){var both:i64=0;var new_only:i64=0;var old_only:i64=0;var diffs:i64=0;var reject_diff:i64=0;
 for arg in ["U32","Bool"] {for result in ["U32","Bool"] {for form in 2 {for body in ["return x\n","return 0\n","return 1\n","return 4294967295\n","return #True\n","return #False\n","return x < 7\n","return 7 < x\n","return U32.wrapping_add(x,1)\n","return x && #True\n","return x || #False\n","if x:\n    return 1\n  return 2\n","let y = x\n  return y\n"] {
 let typ=if form==0 {str(arg," -> ",result)} else {str("Fn[static,Many,",arg,",",result,"]")};let source=str("pub let f: ",typ," ! {} resources {depth: 1, frame: 0} = fn x => do:\n  ",body);let old=typed_dispatch::compile(source);let n=primary_dispatch::compile(source);
 if old.status==0 && n.status==0 {assert(primary_dispatch::previous_recognizes(source));let injected=primary_dispatch::compile_with_fault(source,7);assert(injected.status!=0 && injected.wasm.len==0);both+=1;if old.wasm[..]!=n.wasm[..] || old.argument!=n.argument || old.result!=n.result {diffs+=1;print("DIFF ",source);}}
 else if old.status==0 {old_only+=1;print("OLD_ONLY ",source);}
 else if n.status==0 {new_only+=1;}
 else if old.status!=n.status {reject_diff+=1;print("REJECT_DIFF ",old.status," ",n.status," ",source);}
 }}}}
 assert(old_only==0 && diffs==0 && reject_diff==0 && both>0 && new_only>0);
 print("MATRIX both=",both," new_only=",new_only," old_only=",old_only," bytes_diff=",diffs," reject_diff=",reject_diff);
}
