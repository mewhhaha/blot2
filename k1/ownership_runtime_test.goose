import owned_scalar_source;
import owned_scalar_runtime;
import ownership_parse;
import ownership_check;
import ownership_runtime;
fn main() {
 let scalar="owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,4294967295)\n";
 let core=owned_scalar_source::parse(scalar);assert(core.status==0);
 let text="do:\n  let first = original\n  let second = first\n  let x = owned.open(second) as outer item_a in do:\n    let y = owned.open(second) as inner item_b in do:\n      break item_b\n    break item_a\n  let z = owned.open(second) as again item_c in do:\n    if condition:\n      break item_c\n    else:\n      break item_c\n  owned.close(second)\n  return x\n";
 let transfer="do:\n  if condition:\n    let moved = original\n    return moved\n  else:\n    return original\n";
 let close="do:\n  if condition:\n    owned.close(original)\n    return ()\n  owned.close(original)\n  return ()\n";
 var p=ownership_parse::parse(text);var q=ownership_parse::parse(transfer);var r=ownership_parse::parse(close);
 assert(p.status==0 && q.status==0 && r.status==0);
 var c=ownership_check::Contract {owner:"original",flag:"condition",return_mode:2};
 var d=ownership_check::Contract {owner:"original",flag:"condition",return_mode:1};
 var e=ownership_check::Contract {owner:"original",flag:"condition",return_mode:0};
 var clock=owned_scalar_runtime::Clock {};var state=owned_scalar_runtime::State {};assert(owned_scalar_runtime::initialize(state,clock));
 for choice in 2 {
  let built=owned_scalar_runtime::construct(state,scalar,core.core);assert(built.status==0);
  let done=ownership_runtime::run(p.tree,text,c,state,built.handle,choice==1);
  assert(done.status==0 && done.value==4294967295 && !done.returned_owner && state.slot==0 && state.bitmap[0]==0 && state.loan_count==0);
  let second=owned_scalar_runtime::construct(state,scalar,core.core);assert(second.status==0);
  let moved=ownership_runtime::run(q.tree,transfer,d,state,second.handle,choice==1);
  assert(moved.status==0 && moved.returned_owner && owned_scalar_runtime::live(state,moved.handle));
  if choice==1 {assert(!owned_scalar_runtime::live(state,second.handle));}
  assert(owned_scalar_runtime::close(state,moved.handle).status==0);
  let third=owned_scalar_runtime::construct(state,scalar,core.core);assert(third.status==0);
  assert(ownership_runtime::run(r.tree,close,e,state,third.handle,choice==1).status==0);
  assert(state.slot==0 && state.bitmap[0]==0 && state.loan_count==0);
 }
 let live=owned_scalar_runtime::construct(state,scalar,core.core);assert(live.status==0);
 let old=state.stamp;let memory=copy(state.memory);
 assert(ownership_runtime::run(p.tree,transfer,c,state,live.handle,true).status==1);
 assert(owned_scalar_runtime::live(state,live.handle) && state.stamp==old && state.memory[..]==memory[..]);
 let loan=owned_scalar_runtime::open(state,live.handle);assert(loan.status==0);
 assert(ownership_runtime::run(p.tree,text,c,state,live.handle,false).status==1);
 assert(state.loan_count==1 && owned_scalar_runtime::live(state,live.handle));
 assert(owned_scalar_runtime::end_open(state,live.handle,loan.loan).status==0);
 assert(owned_scalar_runtime::close(state,live.handle).status==0);
 print("general-named ownership execution and nested openings passed");
}
