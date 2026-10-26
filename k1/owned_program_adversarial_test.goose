import owned_scalar_runtime;
import owned_program_source;
import owned_program_verify;
import owned_program_runtime;
fn invalid(s: u8[:], c: owned_program_source::Core) {
  assert(!owned_program_verify::verify(s,c));
  var clock = owned_scalar_runtime::Clock {}; var state = owned_scalar_runtime::State {};
  assert(owned_scalar_runtime::initialize(state,clock));
  let memory = copy(state.memory); let before = state.slots[0];
  assert(owned_program_runtime::run(state,s,c).status == 3);
  assert(state.slot == 0 && state.bitmap[0] == 0 && state.loan_count == 0 && state.stamp == 0 &&
         state.slots[0].state == before.state && state.slots[0].generation == before.generation && state.memory[..] == memory[..]);
}
fn main() {
 let src = "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let m = h\n    let value = owned.open(m) as s payload in do:\n      break payload\n    owned.close(m)\n    return #Ok(value)\n";
 let p = owned_program_source::parse(src); assert(p.status == 0 && owned_program_verify::verify(src,p.core));
 for x in [-1 as i64, 0, 1, 99999999, 9223372036854775807] {
   if x != p.core.owned_start { var f = p.core; f.owned_start = x; invalid(src,f); }
   if x != p.core.owned_end { var f = p.core; f.owned_end = x; invalid(src,f); }
 }
 for x in [0 as u32, 1, 2, 4294967295] {
   if x != p.core.owned.work_bytes { var f = p.core; f.owned.work_bytes = x; invalid(src,f); }
   if x != p.core.owned.terminal { var f = p.core; f.owned.terminal = x; invalid(src,f); }
   if x != p.core.owned.value { var f = p.core; f.owned.value = x; invalid(src,f); }
 }
 var moved = p.core; moved.moved = false; invalid(src,moved);
 var clock = owned_scalar_runtime::Clock {}; var state = owned_scalar_runtime::State {}; assert(owned_scalar_runtime::initialize(state,clock));
 for i in 200 {
   let result = owned_program_runtime::run(state,src,p.core);
   assert(result.status == 0 && result.value == 7 && state.slot == 0 && state.loan_count == 0 && state.bitmap[0] == 0 && state.slots[0].state == 0);
   assert(state.slots[0].generation == (i+1) as u32);
 }
 print("forged program-Core offsets/fields and repeated cleanup passed");
}
