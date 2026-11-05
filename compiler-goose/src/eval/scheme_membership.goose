namespace blot_eval_scheme_membership;
import check.types;
import support.error;
import support.native;
import support.pooled_map;
import work_counters;

import std;
import dictionary;
type List=blot_check_types::List;
struct Key { owner: u64,span: List }
fn hash(key: Key) -> u64 { return ::hash_combine(::hash(key.owner),::hash((key.span.start as u64)<<32|key.span.len)); }
struct View { values: const u32[:],sorted: bool=false }
fn contains(self_: View,value: u32) -> bool {
 if !self_.sorted { for item in self_.values { if item==value { return true; } } return false; }
 var low=0; var high=self_.values.len; while low<high { let mid=low+(high-low)/2; if self_.values[mid]<value { low=mid+1; } else { high=mid; } } return low<self_.values.len&&self_.values[low]==value;
}
struct EntryMap { count: i64=0,slots: dictionary_slot<Key,List>[:]=default<dictionary_slot<Key,List>[:]>() }
reusable[] var pool_EntryMap: dictionary_slot<Key,List>[>..]=[];
fn get(self_: const EntryMap&,key: Key) -> List? { let view=blot_support_pooled_map::Map<Key,List> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self_: const EntryMap&,key: Key) -> bool { return self_.get(key)!=null; }
fn insert(self_: EntryMap&,key: Key,value: List) { var view=blot_support_pooled_map::Map<Key,List> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_EntryMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: EntryMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: EntryMap&) { if self_.slots.len!=0 { pool_EntryMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<Key,List>[:]>(); self_.count=0; }
fn restore(self_: EntryMap&,slots: const dictionary_slot<Key,List>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=pool_EntryMap.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct RetiredWords { values: u32[:]=default<u32[:]>(),next: u32=0 }
reusable[] var membership_words: u32[>..]=[];
reusable var retired_words: RetiredWords[>..]=[];
struct StableWords { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),len: i64=0,retired: u32=0 }
fn append(self_: StableWords&,values: const u32[:]) { let needed=self_.len+values.len; if needed>self_.storage.len { let capacity=max(8,needed+needed/2); let replacement=membership_words.alloc_slice(capacity); for word,index in self_.items { replacement[index]=word; } if self_.storage.len!=0 { let at=retired_words.alloc_index(RetiredWords {self_.storage,self_.retired}); self_.retired=(at+1) as u32; } self_.storage=replacement; } for word,index in values { self_.storage[self_.len+index]=word; } self_.len=needed; self_.items=self_.storage[..needed]; }
fn clear(self_: StableWords&) { self_.len=0; self_.items=self_.storage[..0]; }
fn deinit(self_: StableWords&) { if self_.storage.len!=0 { membership_words.free_slice(self_.storage); } var next=self_.retired; while next!=0 { let at=next-1; let retired=retired_words[at]; next=retired.next; membership_words.free_slice(retired.values); retired_words.free(at); } self_=StableWords {}; }
struct CacheState { entries: EntryMap=EntryMap {},words: StableWords=StableWords {},owner_id: u64=0,items: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Cache_states: CacheState[>..]=[];
var inactive_Cache: CacheState=CacheState {};
var next_Cache_generation: u64=1;
struct Cache { entries: EntryMap& =inactive_Cache.entries,words: StableWords& =inactive_Cache.words,owner_id: u64& =inactive_Cache.owner_id,items: i64& =inactive_Cache.items,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Cache,blot_error::Error { if next_Cache_generation==0xffffffffffffffff||Cache_states.len>=0xffffffff { return Cache {},blot_error::Error.out_of_memory; } let generation=next_Cache_generation; next_Cache_generation++; let index=Cache_states.alloc_index(CacheState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: CacheState& =Cache_states[index]; return Cache {entries:state.entries,words:state.words,owner_id:state.owner_id,items:state.items,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self_: Cache&) { if self_.lease==0 { return; } let index=self_.lease-1; assert(index<Cache_states.len&&Cache_states[index].live&&Cache_states[index].lease_generation==self_.lease_generation); release(self_.entries); self_.words.deinit(); Cache_states[index].live=false; Cache_states.free(index); self_=Cache {}; }
fn prepare(self_: Cache&,stats: blot_work_counters::SchemeMembership&,owner: u64,span: List,values: const u32[:]) -> View {
 stats.prepares++; if values.len<=16 { stats.small++; return View {values,false}; }
 if values.len>16384||owner==0 { stats.saturated++; return View {values,false}; }
 let key=Key {owner,span}; let known=self_.entries.get(key);
 if known { stats.hits++; return View {self_.words.items[known.start..known.start+known.len],true}; }
 if self_.entries.count>=64||values.len>16384-self_.items { stats.saturated++; return View {values,false}; }
 let sorted=membership_words.alloc_slice(values.len); for value,index in values { sorted[index]=value; } ::sort(sorted); let saved=List {self_.words.len as u32,sorted.len as u32}; self_.words.append(sorted); self_.entries.insert(key,saved); self_.items+=sorted.len; stats.publications++; stats.indexed_items+=sorted.len; membership_words.free_slice(sorted); return View {self_.words.items[saved.start..saved.start+saved.len],true};
}
