namespace blot_eval_eval_collection_growth;
import dictionary;
import support.pooled_map;
import .eval_values;
import std;
import support.error;
import support.native;
struct Span { start: u32, len: u32 }
struct Frontier { offset: u32, capacity: u32 }
struct BufferEffect { value: u32, frontier: Frontier }
fn hash(value: Span) -> u64 { return hash((value.start as u64)<<32|value.len); }
struct BufferMap { count: i64=0,slots: dictionary_slot<Span,Span>[:]=[] }
reusable[] var pool_BufferMap: dictionary_slot<Span,Span>[>..]=[];
fn get(self: const BufferMap&,key: Span) -> Span? { let view=blot_support_pooled_map::Map<Span,Span> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const BufferMap&,key: Span) -> bool { return self.get(key)!=null; }
fn insert(self: BufferMap&,key: Span,value: Span) { var view=blot_support_pooled_map::Map<Span,Span> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_BufferMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: BufferMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: BufferMap&) { if self.slots.len!=0 { pool_BufferMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: BufferMap&,slots: const dictionary_slot<Span,Span>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_BufferMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct StoreState { buffers: BufferMap=BufferMap {},owner_id: u64=0,mutation_serial: u64=0,lease_generation: u64=0,live: bool=false }
reusable var Store_states: StoreState[>..]=[];
var inactive_Store: StoreState=StoreState {};
var next_Store_generation: u64=1;
struct Store { buffers: BufferMap&=inactive_Store.buffers,owner_id: u64&=inactive_Store.owner_id,mutation_serial: u64&=inactive_Store.mutation_serial,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Store,blot_error::Error { if next_Store_generation==0xffffffffffffffff||Store_states.len>=0xffffffff { return Store {},blot_error::Error.out_of_memory; } let generation=next_Store_generation; next_Store_generation++; let index=Store_states.alloc_index(StoreState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: StoreState&=Store_states[index]; return Store {buffers:state.buffers,owner_id:state.owner_id,mutation_serial:state.mutation_serial,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self: Store&) { if self.lease==0 { return; } let index=self.lease-1; assert(index<Store_states.len&&Store_states[index].live&&Store_states[index].lease_generation==self.lease_generation); release(self.buffers); Store_states[index].live=false; Store_states.free(index); self=Store {}; }
fn mutation(self: Store&) { if self.mutation_serial!=0xffffffffffffffff { self.mutation_serial++; } }
fn extend(self: Store&,children: blot_eval_eval_values::Words&,before: Span,value: u32,front: bool,maximum: i64) -> Span,blot_error::Error {
 var limit=maximum; if limit>0xffffffff { limit=0xffffffff; }
 if children.len>limit||before.len==0xffffffff { return Span {0,0},blot_error::Error.limit; }
 let length=before.len+1; let found=self.buffers.get(before);
 if found!=null {
  let buffer=found; let offset=before.start-buffer.start; var room=before.len<buffer.len-offset; if front { room=offset!=0; }
  if room {
   var start=before.start; if front { start--; } let after=Span {start,length}; self.buffers.remove(before);
   var slot=before.start+before.len; if front { slot=after.start; } children.items[slot]=value; self.buffers.insert(after,buffer); mutation(self); return after,blot_error::Error.none;
  }
 }
 let available=limit-children.len; if length>available { return Span {0,0},blot_error::Error.limit; }
 var capacity=(length as i64)*2; if capacity<16 { capacity=16; } if capacity>available { capacity=available; }
 let buffer=Span {children.len as u32,capacity as u32}; let after=Span {buffer.start+(buffer.len-length)/2,length}; children.resize(children.len+capacity,0);
 var shift: u32=0; if front { shift=1; } for i in 0..before.len { children.items[after.start+shift+i]=children.items[before.start+i]; }
 var slot=after.start+before.len; if front { slot=after.start; } children.items[slot]=value; self.buffers.insert(after,buffer); mutation(self); return after,blot_error::Error.none;
}
