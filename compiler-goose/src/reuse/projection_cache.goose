namespace blot_reuse_projection_cache;
import dictionary;
import support.pooled_map;
import support.error;
type Error=blot_error::Error;
struct Answer { value: u32,visits: u32,height: u16 }
type Answers=blot_support_pooled_map::Map<u32,Answer>;
reusable[] var answer_slots: dictionary_slot<u32,Answer>[>..]=[];
fn get(self_: const Answers&,key: u32) -> Answer? { return blot_support_pooled_map::get(self_,key); }
fn insert(self_: Answers&,key: u32,value: Answer) { blot_support_pooled_map::insert(self_,key,value,answer_slots); }
fn clear(self_: Answers&) { blot_support_pooled_map::clear(self_); }
fn release(self_: Answers&) { blot_support_pooled_map::deinit(self_,answer_slots); }
// Snapshot restoration preserves the original probe slots, including empties.
fn restore(self_: Answers&,slots: const dictionary_slot<u32,Answer>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=answer_slots.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct State { answers: Answers=Answers {},labels: Answers=Answers {},generation: u64=0,live: bool=false }
reusable var states: State[>..]=[];
var inactive: State=State {};
var next_generation: u64=1;
struct Cache {
 answers: Answers& =inactive.answers,labels: Answers& =inactive.labels,
 source: u64=0,target: u64=0,generation: u16=0,physical: u64=0,
 lease: u32=0,lease_generation: u64=0
}
fn initPooled() -> Cache,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Cache {},blot_error::Error.out_of_memory; } let generation=next_generation; next_generation++; let at=states.alloc_index(State {generation:generation,live:true}); let state: State& =states[at]; return Cache {answers:state.answers,labels:state.labels,lease:(at+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn valid(cache: const Cache&) -> bool { return cache.lease!=0&&cache.lease-1<states.len&&states[cache.lease-1].live&&states[cache.lease-1].generation==cache.lease_generation; }
fn deinit(cache: Cache&) { if cache.lease==0 { return; } assert(valid(cache)); release(cache.answers); release(cache.labels); let at=cache.lease-1; states[at].live=false; states.free(at); cache=Cache {}; }
fn clearRetainingCapacity(cache: Cache&) { assert(valid(cache)); cache.answers.clear(); cache.labels.clear(); cache.source=0; cache.target=0; cache.generation=0; cache.physical=0; }
fn activate(cache: Cache&,source: u64,target: u64,generation: u16,physical: u64) -> bool {
 assert(valid(cache));
 if source==0||target==0||cache.source!=source||cache.target!=target||cache.generation!=generation||cache.physical!=physical {
  cache.answers.clear(); cache.labels.clear(); cache.source=source; cache.target=target; cache.generation=generation; cache.physical=physical;
 }
 return source!=0&&target!=0&&generation!=65535&&physical!=18446744073709551615;
}
