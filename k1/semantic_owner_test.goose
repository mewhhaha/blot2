import std;
import semantic_owner;
fn main() {
 let s="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n";
 var r=semantic_owner::build("pkg","src/main.blot","f",s);assert(r.status==0);
 let out=semantic_owner::emit("pkg","src/main.blot","f",s,r.owner,0,128,0,0);assert(out.status==0 && out.wasm.len>0);
 assert(semantic_owner::verify("pkg","src/main.blot","f",s,r.owner,out.wasm));
 assert(!semantic_owner::valid("other","src/main.blot","f",s,r.owner));
 assert(!semantic_owner::valid("pkg","src/other.blot","f",s,r.owner));
 assert(!semantic_owner::valid("pkg","src/main.blot","other",s,r.owner));
 assert(semantic_owner::build("pkg","src/main.blot","other",s).status!=0);
 assert(semantic_owner::build("pkg","../main.blot","f",s).status!=0);
 let fnsource="// leading comment\npub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n";
 var other=semantic_owner::build("pkg","src/main.blot","f",fnsource);assert(other.status==0);
 assert(!semantic_owner::verify("pkg","src/main.blot","f",fnsource,r.owner,out.wasm));
 let fnout=semantic_owner::emit("pkg","src/main.blot","f",fnsource,other.owner,0,128,0,0);assert(fnout.status==0 && semantic_owner::verify("pkg","src/main.blot","f",fnsource,other.owner,fnout.wasm));
 for i in 6 {var o=copy(r.owner);if i==0 {o.origin.package[0]^=1;}else if i==1 {o.origin.module[0]^=1;}else if i==2 {o.origin.declaration[0]^=1;}else if i==3 {o.origin.bytes[0]^=1;}else if i==4 {o.origin.fingerprint[0]^=1;}else {o.origin.fingerprint_domain=2;}
  assert(!semantic_owner::valid("pkg","src/main.blot","f",s,o));let failed=semantic_owner::emit("pkg","src/main.blot","f",s,o,0,128,0,0);assert(failed.status!=0 && failed.wasm.len==0);}
 let no=semantic_owner::emit("pkg","src/main.blot","wrong",s,r.owner,0,128,0,0);assert(no.status!=0 && no.wasm.len==0);
 print("semantic Core job identity, source and target binding passed");
}
