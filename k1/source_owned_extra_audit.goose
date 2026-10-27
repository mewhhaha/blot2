import owned_scalar_source;
import owned_scalar_runtime;
import source_owned_admit;
import source_owned_run;
fn main() {
 let scalar="owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,9)\n";
 let seed=owned_scalar_source::parse(scalar);assert(seed.status==0);
 let unit="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Unit ! {release} = fn (h, flag) => do:\n  if flag:\n    owned.close(h)\n    return ()\n  else:\n    owned.close(h)\n    return ()\n";
 let transfer="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Owned[Scalar[_]] ! {release} = fn (h, flag) => do:\n  if flag:\n    let moved = h\n    return moved\n  else:\n    return h\n";
 var u=source_owned_admit::admit(unit);var p=source_owned_admit::admit(transfer);assert(u.status==0 && p.status==0);
 var clock=owned_scalar_runtime::Clock {};var state=owned_scalar_runtime::State {};assert(owned_scalar_runtime::initialize(state,clock));
 for choice in 2 {
  let item=owned_scalar_runtime::construct(state,scalar,seed.core);assert(item.status==0);
  let done=source_owned_run::run(transfer,p.program,state,item.handle,choice==1);assert(done.status==0 && done.returned_owner && owned_scalar_runtime::live(state,done.handle));
  if choice==1 {assert(!owned_scalar_runtime::live(state,item.handle));}
  assert(owned_scalar_runtime::close(state,done.handle).status==0);
  let item2=owned_scalar_runtime::construct(state,scalar,seed.core);assert(item2.status==0);
  let closed=source_owned_run::run(unit,u.program,state,item2.handle,choice==1);assert(closed.status==0 && !closed.returned_owner && state.slot==0 && state.loan_count==0);
 }
 let h=owned_scalar_runtime::construct(state,scalar,seed.core);assert(h.status==0);
 state.next_loan=18446744073709551360;
 let stamp=state.stamp;let bytes=copy(state.memory);let denied=source_owned_run::run(unit,u.program,state,h.handle,false);
 assert(denied.status!=0 && state.stamp==stamp && state.memory[..]==bytes[..] && owned_scalar_runtime::live(state,h.handle));
 print("source-owned Unit and transfer branches and preflight state passed");
}
