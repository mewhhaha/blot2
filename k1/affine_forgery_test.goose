import affine_parse;
import affine_verify;
import affine_check;
import affine_runtime;
import owned_scalar_source;
import owned_scalar_runtime;
fn main() {
 let source="do:\n  if flag:\n    let value = owned.open(h) as r payload in do:\n      if flag:\n        break payload\n      else:\n        break payload\n    owned.close(h)\n    return ()\n  else:\n    let m = h\n    owned.close(m)\n    return ()\n";
 let payload="owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\n";
 var tree=affine_parse::parse(source);assert(tree.status==0 && affine_check::check(tree.tree,source,0)==0);
 let core=owned_scalar_source::parse(payload);var clock=owned_scalar_runtime::Clock {};var state=owned_scalar_runtime::State {};assert(owned_scalar_runtime::initialize(state,clock));
 let made=owned_scalar_runtime::construct(state,payload,core.core);assert(made.status==0);
 let memory=copy(state.memory);let stamp=state.stamp;let entry=state.slots[0];
 for i in tree.tree.nodes.len {let orig=tree.tree.nodes[i];
  for v in [-1 as i64,0,1,2,256,99999999] {
   for field in 6 {tree.tree.nodes[i]=orig;
     let was=if field==0 {orig.tag} else if field==1 {orig.start} else if field==2 {orig.end} else if field==3 {orig.owner} else if field==4 {orig.a} else {orig.b};
     if field==0 {tree.tree.nodes[i].tag=v;}else if field==1 {tree.tree.nodes[i].start=v;}else if field==2 {tree.tree.nodes[i].end=v;}else if field==3 {tree.tree.nodes[i].owner=v;}else if field==4 {tree.tree.nodes[i].a=v;}else {tree.tree.nodes[i].b=v;}
     if was!=v {assert(!affine_verify::verify(tree.tree) && affine_check::check(tree.tree,source,0)==1);
       assert(affine_runtime::run(tree.tree,source,0,state,made.handle,false).status==1);
       assert(owned_scalar_runtime::live(state,made.handle) && state.slot==1 && state.stamp==stamp && state.loan_count==0 && state.slots[0].generation==entry.generation && state.memory[..]==memory[..]);}
   }
  }
  tree.tree.nodes[i]=orig;
 }
 for bad in [0 as u64,2,18446744073709551615] {var h=made.handle;h.owner=bad;assert(affine_runtime::run(tree.tree,source,0,state,h,true).status==1 && owned_scalar_runtime::live(state,made.handle));}
 assert(owned_scalar_runtime::close(state,made.handle).status==0);
 print("all affine node fields and forged owner preflight rejected without mutation");
}
