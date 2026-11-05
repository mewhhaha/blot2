namespace blot_eval_evidence_import_cache;
import dictionary;
import support.error;
import support.pooled_map;
import support.native;
struct AnswerMap { count: i64=0,slots: dictionary_slot<u64,u32>[:]=[] }
reusable[] var pool_AnswerMap: dictionary_slot<u64,u32>[>..]=[];
fn get(self: const AnswerMap&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const AnswerMap&,key: u64) -> bool { return self.get(key)!=null; }
fn insert(self: AnswerMap&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_AnswerMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: AnswerMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: AnswerMap&) { if self.slots.len!=0 { pool_AnswerMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: AnswerMap&,slots: const dictionary_slot<u64,u32>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_AnswerMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct CacheState { answers: AnswerMap=AnswerMap {},owner_id: u64=0,source: u64=0,target: u64=0,generation: u16=0,physical: u64=0,max_depth: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Cache_states: CacheState[>..]=[];
var inactive_Cache: CacheState=CacheState {};
var next_Cache_generation: u64=1;
struct Cache { answers: AnswerMap&=inactive_Cache.answers,owner_id: u64&=inactive_Cache.owner_id,source: u64&=inactive_Cache.source,target: u64&=inactive_Cache.target,generation: u16&=inactive_Cache.generation,physical: u64&=inactive_Cache.physical,max_depth: i64&=inactive_Cache.max_depth,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Cache,blot_error::Error { if next_Cache_generation==0xffffffffffffffff||Cache_states.len>=0xffffffff { return Cache {},blot_error::Error.out_of_memory; } let generation=next_Cache_generation; next_Cache_generation++; let index=Cache_states.alloc_index(CacheState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: CacheState&=Cache_states[index]; return Cache {answers:state.answers,owner_id:state.owner_id,source:state.source,target:state.target,generation:state.generation,physical:state.physical,max_depth:state.max_depth,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self: Cache&) { if self.lease==0 { return; } let index=self.lease-1; assert(index<Cache_states.len&&Cache_states[index].live&&Cache_states[index].lease_generation==self.lease_generation); release(self.answers); Cache_states[index].live=false; Cache_states.free(index); self=Cache {}; }
fn clearRetainingCapacity(self: Cache&) { self.answers.clear(); self.source=0; self.target=0; self.generation=0; self.physical=0; self.max_depth=0; }
fn activate(self: Cache&,source: u64,target: u64,generation: u16,physical: u64,max_depth: i64) -> bool {
 if source!=0&&target!=0&&self.source==source&&self.target==target&&self.generation==generation&&self.physical==physical&&self.max_depth==max_depth { return false; }
 self.answers.clear(); self.source=source; self.target=target; self.generation=generation; self.physical=physical; self.max_depth=max_depth; return true;
}
fn key(self: Cache&,value: u32,depth: i64) -> u64,bool {
 if self.source==0||self.target==0||self.generation==0xffff||self.physical==0xffffffffffffffff||depth<0||depth>0xffffffff { return 0,false; }
 return ((value as u64)<<32)|(depth as u64),true;
}
