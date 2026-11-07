namespace blot_eval_evidence_import_cache;
import support.error;
import support.native;
import support.pooled_map;

import dictionary;
struct AnswerMap { count: i64=0,slots: dictionary_slot<u64,u32>[:]=default<dictionary_slot<u64,u32>[:]>() }
reusable[] var pool_AnswerMap: dictionary_slot<u64,u32>[>..]=[];
fn get(self_: const AnswerMap&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self_: const AnswerMap&,key: u64) -> bool { return self_.get(key)!=null; }
fn insert(self_: AnswerMap&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_AnswerMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: AnswerMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: AnswerMap&) { if self_.slots.len!=0 { pool_AnswerMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,u32>[:]>(); self_.count=0; }
fn restore(self_: AnswerMap&,slots: const dictionary_slot<u64,u32>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=pool_AnswerMap.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct CacheState { answers: AnswerMap=AnswerMap {},owner_id: u64=0,source: u64=0,target: u64=0,generation: u16=0,physical: u64=0,max_depth: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Cache_states: CacheState[>..]=[];
var inactive_Cache: CacheState=CacheState {};
var next_Cache_generation: u64=1;
struct Cache { answers: AnswerMap& =inactive_Cache.answers,owner_id: u64& =inactive_Cache.owner_id,source: u64& =inactive_Cache.source,target: u64& =inactive_Cache.target,generation: u16& =inactive_Cache.generation,physical: u64& =inactive_Cache.physical,max_depth: i64& =inactive_Cache.max_depth,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Cache,blot_error::Error { if next_Cache_generation==0xffffffffffffffff||Cache_states.len>=0xffffffff { return Cache {},blot_error::Error.out_of_memory; } let generation=next_Cache_generation; next_Cache_generation++;         let __field_order_294_lease_generation: u64 = generation; let __field_order_295_live: bool = true; let __field_order_296_owner_id: u64 = blot_native::fresh_owner_id(); let index=Cache_states.alloc_index(CacheState { owner_id: __field_order_296_owner_id, lease_generation: __field_order_294_lease_generation, live: __field_order_295_live }); let state: CacheState& =Cache_states[index]; return Cache {answers:state.answers,owner_id:state.owner_id,source:state.source,target:state.target,generation:state.generation,physical:state.physical,max_depth:state.max_depth,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self_: Cache&) { if self_.lease==0 { return; } let index=self_.lease-1; assert(index<Cache_states.len&&Cache_states[index].live&&Cache_states[index].lease_generation==self_.lease_generation); release(self_.answers); Cache_states[index].live=false; Cache_states.free(index); self_=Cache {}; }
fn clearRetainingCapacity(self_: Cache&) { self_.answers.clear(); self_.source=0; self_.target=0; self_.generation=0; self_.physical=0; self_.max_depth=0; }
fn activate(self_: Cache&,source: u64,target: u64,generation: u16,physical: u64,max_depth: i64) -> bool {
 if source!=0&&target!=0&&self_.source==source&&self_.target==target&&self_.generation==generation&&self_.physical==physical&&self_.max_depth==max_depth { return false; }
 self_.answers.clear(); self_.source=source; self_.target=target; self_.generation=generation; self_.physical=physical; self_.max_depth=max_depth; return true;
}
fn key(self_: Cache&,value: u32,depth: i64) -> u64,bool {
 if self_.source==0||self_.target==0||self_.generation==0xffff||self_.physical==0xffffffffffffffff||depth<0||depth>0xffffffff { return 0,false; }
 return ((value as u64)<<32)|(depth as u64),true;
}
