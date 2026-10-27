import std;
import semantic_leaf_lift_check;
fn main() {
 for d in ["1","2","127","128"] {for name in ["f","other"] {
  let source=str("// prefix\npub let ",name,": Fn[static,Many,U32,U32] ! {} resources {depth: ",d,", frame: 0} = fn parameter => do:\n  return parameter\n");
  let synthetic=str("pub let ",name,": U32 -> U32 ! {} resources {depth: ",d,", frame: 0} = fn q => return q\n");
  assert(semantic_leaf_lift_check::proof("pkg","x.blot",source,synthetic));
  let other=str("pub let ",name,": U32 -> U32 ! {} resources {depth: ",d,", frame: 0} = fn q => return 0\n");
  assert(!semantic_leaf_lift_check::proof("pkg","x.blot",source,other));
  for v in ["0","1","2147483647","2147483648","4294967295"] {
   let literal=str("pub let ",name,": U32 -> U32 ! {} resources {depth: ",d,", frame: 0} = fn a => do:\n  return ",v,"\n");
   let target=str("pub let ",name,": U32 -> U32 ! {} resources {depth: ",d,", frame: 0} = fn b => return ",v,"\n");
   assert(semantic_leaf_lift_check::proof("pkg","x.blot",literal,target));
   assert(!semantic_leaf_lift_check::proof("pkg","x.blot",literal,synthetic));
   let wrong=str("pub let ",name,": U32 -> U32 ! {} resources {depth: ",d,", frame: 0} = fn b => return ",if v=="0" {"1"} else {"0"},"\n");
   assert(!semantic_leaf_lift_check::proof("pkg","x.blot",literal,wrong));
   assert(!semantic_leaf_lift_check::proof("wrong/pkg","../x.blot",literal,target));
  }
 }}
 print("independent multiline identity/literal source/synthetic boundary matrix passed");
}
