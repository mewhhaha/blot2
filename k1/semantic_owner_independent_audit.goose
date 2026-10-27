import std;import semantic_owner;
fn main(){
 let s="// prefix before declaration\npub let funny: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  return x\n";
 var r=semantic_owner::build("pkg","src/main.blot","funny",s);assert(r.status==0 && semantic_owner::valid("pkg","src/main.blot","funny",s,r.owner));
 let o=semantic_owner::emit("pkg","src/main.blot","funny",s,r.owner,0,128,0,7);assert(o.status==0 && semantic_owner::verify("pkg","src/main.blot","funny",s,r.owner,o.wasm));
 for i in 8 {var c=copy(r.owner);if i==0 {c.core.program.head.let_start=-1;}else if i==1 {c.core.program.head.let_start=9223372036854775807;}else if i==2 {c.core.program.name_start=-1;}else if i==3 {c.core.program.name_start=9223372036854775807;}else if i==4 {c.core.program.name_end=9223372036854775807;}else if i==5 {c.core.program.name_end=c.core.program.name_start;}else if i==6 {c.origin.bytes[0]^=1;}else {c.origin.declaration[0]^=1;}
 assert(!semantic_owner::valid("pkg","src/main.blot","funny",s,c));let x=semantic_owner::emit("pkg","src/main.blot","funny",s,c,0,128,0,7);assert(x.status!=0 && x.wasm.len==0);}
 for name in ["fun","unny","funnx","other","../funny",""] {assert(semantic_owner::build("pkg","src/main.blot",name,s).status!=0);}
 let fail=semantic_owner::emit("pkg","src/main.blot","funny",s,r.owner,126,128,0,7);assert(fail.status==2 && fail.wasm.len==0);
 print("independent semantic identity offset and failure checks passed");
}
