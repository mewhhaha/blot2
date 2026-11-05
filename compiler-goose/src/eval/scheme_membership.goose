namespace blot_eval_scheme_membership;
import std;
import dictionary;
import support.error;
import support.pooled_map;
import check.types;
import work_counters;
import support.native;
type List=blot_check_types::List;
struct Key { owner: u64,span: List }
fn hash(key: Key) -> u64 { return ::hash_combine(::hash(key.owner),::hash((key.span.start as u64)<<32|key.span.len)); }
struct View { values: const u32[:],sorted: bool=false }
fn contains(self: View,value: u32) -> bool {
 if !self.sorted { for item in self.values { if item==value { return true; } } return false; }
 var low=0; var high=self.values.len; while low<high { let mid=low+(high-low)/2; if self.values[mid]<value { low=mid+1; } else { high=mid; } } return low<self.values.len&&self.values[low]==value;
}
struct EntryMap { count: i64=0,slots: dictionary_slot<Key,List>[:]=[] }
reusable[] var pool_EntryMap: dictionary_slot<Key,List>[>..]=[];
fn get(self: const EntryMap&,key: Key) -> List? { let view=blot_support_pooled_map::Map<Key,List> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const EntryMap&,key: Key) -> bool { return self.get(key)!=null; }
fn insert(self: EntryMap&,key: Key,value: List) { var view=blot_support_pooled_map::Map<Key,List> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_EntryMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: EntryMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: EntryMap&) { if self.slots.len!=0 { pool_EntryMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: EntryMap&,slots: const dictionary_slot<Key,List>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_EntryMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct RetiredWords { values: u32[:]=[],next: u32=0 }
reusable[] var membership_words: u32[>..]=[];
reusable var retired_words: RetiredWords[>..]=[];
struct StableWords { storage: u32[:]=[],items: u32[:]=[],len: i64=0,retired: u32=0 }
fn append(self: StableWords&,values: const u32[:]) { let needed=self.len+values.len; if needed>self.storage.len { let capacity=max(8,needed+needed/2); let replacement=membership_words.alloc_slice(capacity); for word,index in self.items { replacement[index]=word; } if self.storage.len!=0 { let at=retired_words.alloc_index(RetiredWords {self.storage,self.retired}); self.retired=(at+1) as u32; } self.storage=replacement; } for word,index in values { self.storage[self.len+index]=word; } self.len=needed; self.items=self.storage[..needed]; }
fn clear(self: StableWords&) { self.len=0; self.items=self.storage[..0]; }
fn deinit(self: StableWords&) { if self.storage.len!=0 { membership_words.free_slice(self.storage); } var next=self.retired; while next!=0 { let at=next-1; let retired=retired_words[at]; next=retired.next; membership_words.free_slice(retired.values); retired_words.free(at); } self=StableWords {}; }
struct CacheState { entries: EntryMap=EntryMap {},words: StableWords=StableWords {},owner_id: u64=0,items: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Cache_states: CacheState[>..]=[];
var inactive_Cache: CacheState=CacheState {};
var next_Cache_generation: u64=1;
struct Cache { entries: EntryMap&=inactive_Cache.entries,words: StableWords&=inactive_Cache.words,owner_id: u64&=inactive_Cache.owner_id,items: i64&=inactive_Cache.items,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Cache,blot_error::Error { if next_Cache_generation==0xffffffffffffffff||Cache_states.len>=0xffffffff { return Cache {},blot_error::Error.out_of_memory; } let generation=next_Cache_generation; next_Cache_generation++; let index=Cache_states.alloc_index(CacheState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: CacheState&=Cache_states[index]; return Cache {entries:state.entries,words:state.words,owner_id:state.owner_id,items:state.items,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self: Cache&) { if self.lease==0 { return; } let index=self.lease-1; assert(index<Cache_states.len&&Cache_states[index].live&&Cache_states[index].lease_generation==self.lease_generation); release(self.entries); self.words.deinit(); Cache_states[index].live=false; Cache_states.free(index); self=Cache {}; }
fn prepare(self: Cache&,stats: blot_work_counters::SchemeMembership&,owner: u64,span: List,values: const u32[:]) -> View {
 stats.prepares++; if values.len<=16 { stats.small++; return View {values,false}; }
 if values.len>16384||owner==0 { stats.saturated++; return View {values,false}; }
 let key=Key {owner,span}; let known=self.entries.get(key);
 if known { stats.hits++; return View {self.words.items[known.start..known.start+known.len],true}; }
 if self.entries.count>=64||values.len>16384-self.items { stats.saturated++; return View {values,false}; }
 let sorted=membership_words.alloc_slice(values.len); for value,index in values { sorted[index]=value; } ::sort(sorted); let saved=List {self.words.len as u32,sorted.len as u32}; self.words.append(sorted); self.entries.insert(key,saved); self.items+=sorted.len; stats.publications++; stats.indexed_items+=sorted.len; membership_words.free_slice(sorted); return View {self.words.items[saved.start..saved.start+saved.len],true};
}
