namespace blot_eval_eval_collection_growth;
import dictionary;
import std;
import support.error;
import support.native;
struct Span { start: u32, len: u32 }
struct Frontier { offset: u32, capacity: u32 }
struct BufferEffect { value: u32, frontier: Frontier }
fn hash(value: Span) -> u64 { return hash((value.start as u64)<<32|value.len); }
struct Store { owner_id: u64=blot_native::fresh_owner_id(), buffers: dictionary<Span,Span>&, mutation_serial: u64=0 }
fn init(buffers: dictionary<Span,Span>&) -> Store { return Store {buffers:buffers}; }
fn mutation(self: Store&) { if self.mutation_serial!=0xffffffffffffffff { self.mutation_serial++; } }
fn extend(self: Store&,children: u32[>..<]&,before: Span,value: u32,front: bool,maximum: i64) -> Span,blot_error::Error {
 var limit=maximum; if limit>0xffffffff { limit=0xffffffff; }
 if children.len>limit||before.len==0xffffffff { return Span {0,0},blot_error::Error.limit; }
 let length=before.len+1; let found=self.buffers.get(before);
 if found!=null {
  let buffer=found; let offset=before.start-buffer.start; var room=before.len<buffer.len-offset; if front { room=offset!=0; }
  if room {
   var start=before.start; if front { start--; } let after=Span {start,length}; self.buffers.remove(before);
   var slot=before.start+before.len; if front { slot=after.start; } children[slot]=value; self.buffers.insert(after,buffer); mutation(self); return after,blot_error::Error.none;
  }
 }
 let available=limit-children.len; if length>available { return Span {0,0},blot_error::Error.limit; }
 var capacity=(length as i64)*2; if capacity<16 { capacity=16; } if capacity>available { capacity=available; }
 let buffer=Span {children.len as u32,capacity as u32}; let after=Span {buffer.start+(buffer.len-length)/2,length}; children.resize(children.len+capacity,0);
 var shift: u32=0; if front { shift=1; } for i in 0..before.len { children[after.start+shift+i]=children[before.start+i]; }
 var slot=after.start+before.len; if front { slot=after.start; } children[slot]=value; self.buffers.insert(after,buffer); mutation(self); return after,blot_error::Error.none;
}
