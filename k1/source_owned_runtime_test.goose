import owned_scalar_source;
import owned_scalar_runtime;
import source_owned_admit;
import source_owned_run;
fn main() {
 let scalar="owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,4294967295)\n";
 let seed=owned_scalar_source::parse(scalar);assert(seed.status==0);
 let s="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  owned.close(h)\n  return value\n";
 let wrong="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  return value\n";
 let rejected=source_owned_admit::admit(wrong);assert(rejected.status!=0 && rejected.program.source.len==0 && rejected.program.tree.nodes.len==0);
 var p=source_owned_admit::admit(s);assert(p.status==0);
 var clock=owned_scalar_runtime::Clock {};var state=owned_scalar_runtime::State {};assert(owned_scalar_runtime::initialize(state,clock));
 for choice in 2 {let made=owned_scalar_runtime::construct(state,scalar,seed.core);assert(made.status==0);let stamp=state.stamp;let memory=copy(state.memory);
  assert(source_owned_run::run(wrong,p.program,state,made.handle,choice==1).status!=0);
  assert(owned_scalar_runtime::live(state,made.handle) && state.stamp==stamp && state.memory[..]==memory[..] && state.loan_count==0);
  let result=source_owned_run::run(s,p.program,state,made.handle,choice==1);assert(result.status==0 && result.value==4294967295 && !result.returned_owner && state.loan_count==0 && state.slot==0);
 }
 print("source-derived ownership admission and native execution passed");
}
