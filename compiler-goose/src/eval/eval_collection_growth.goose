namespace blot_eval_eval_collection_growth;
import eval.eval_values;
import support.error;
import support.native;
import support.pooled_map;

import dictionary;
import std;
struct Span { start: u32, len: u32 }
struct Frontier { offset: u32, capacity: u32 }
struct BufferEffect { value: u32, frontier: Frontier }
fn hash(value: Span) -> u64 { return hash((value.start as u64)<<32|value.len); }
struct BufferMap { count: i64=0,slots: dictionary_slot<Span,Span>[:]=default<dictionary_slot<Span,Span>[:]>() }
reusable[] var pool_BufferMap: dictionary_slot<Span,Span>[>..]=[];
fn get(self_: const BufferMap&,key: Span) -> Span? { let view=blot_support_pooled_map::Map<Span,Span> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self_: const BufferMap&,key: Span) -> bool { return self_.get(key)!=null; }
fn insert(self_: BufferMap&,key: Span,value: Span) { var view=blot_support_pooled_map::Map<Span,Span> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_BufferMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: BufferMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: BufferMap&) { if self_.slots.len!=0 { pool_BufferMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<Span,Span>[:]>(); self_.count=0; }
fn restore(self_: BufferMap&,slots: const dictionary_slot<Span,Span>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=pool_BufferMap.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct StoreState { buffers: BufferMap=BufferMap {},owner_id: u64=0,mutation_serial: u64=0,lease_generation: u64=0,live: bool=false }
reusable var Store_states: StoreState[>..]=[];
var inactive_Store: StoreState=StoreState {};
var next_Store_generation: u64=1;
struct Store { buffers: BufferMap& =inactive_Store.buffers,owner_id: u64& =inactive_Store.owner_id,mutation_serial: u64& =inactive_Store.mutation_serial,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Store,blot_error::Error { if next_Store_generation==0xffffffffffffffff||Store_states.len>=0xffffffff { return Store {},blot_error::Error.out_of_memory; } let generation=next_Store_generation; next_Store_generation++;         let __field_order_297_lease_generation: u64 = generation; let __field_order_298_live: bool = true; let __field_order_299_owner_id: u64 = blot_native::fresh_owner_id(); let index=Store_states.alloc_index(StoreState { owner_id: __field_order_299_owner_id, lease_generation: __field_order_297_lease_generation, live: __field_order_298_live }); let state: StoreState& =Store_states[index]; return Store {buffers:state.buffers,owner_id:state.owner_id,mutation_serial:state.mutation_serial,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self_: Store&) { if self_.lease==0 { return; } let index=self_.lease-1; assert(index<Store_states.len&&Store_states[index].live&&Store_states[index].lease_generation==self_.lease_generation); release(self_.buffers); Store_states[index].live=false; Store_states.free(index); self_=Store {}; }
fn mutation(self_: Store&) { if self_.mutation_serial!=0xffffffffffffffff { self_.mutation_serial++; } }
fn extend(self_: Store&,children: blot_eval_eval_values::Words&,before: Span,value: u32,front: bool,maximum: i64) -> Span,blot_error::Error {
 var limit=maximum; if limit>0xffffffff { limit=0xffffffff; }
 if children.len>limit||before.len==0xffffffff { return Span {0,0},blot_error::Error.limit; }
 let length=before.len+1; let found=self_.buffers.get(before);
 if found!=null {
  let buffer=found; let offset=before.start-buffer.start; var room=before.len<buffer.len-offset; if front { room=offset!=0; }
  if room {
   var start=before.start; if front { start--; } let after=Span {start,length}; self_.buffers.remove(before);
   var slot=before.start+before.len; if front { slot=after.start; } children.items[slot]=value; self_.buffers.insert(after,buffer); mutation(self_); return after,blot_error::Error.none;
  }
 }
 let available=limit-children.len; if length>available { return Span {0,0},blot_error::Error.limit; }
 var capacity=(length as i64)*2; if capacity<16 { capacity=16; } if capacity>available { capacity=available; }
 let buffer=Span {children.len as u32,capacity as u32}; let after=Span {buffer.start+(buffer.len-length)/2,length}; children.resize(children.len+capacity,0);
 var shift: u32=0; if front { shift=1; } for i in 0..before.len { children.items[after.start+shift+i]=children.items[before.start+i]; }
 var slot=after.start+before.len; if front { slot=after.start; } children.items[slot]=value; self_.buffers.insert(after,buffer); mutation(self_); return after,blot_error::Error.none;
}

fn remove(self_: BufferMap&,key: Span) -> bool { var view=blot_support_pooled_map::Map<Span,Span> {count:self_.count,slots:self_.slots}; let result=blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; return result; }
