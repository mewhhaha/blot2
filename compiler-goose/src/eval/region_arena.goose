// Byte buffers only. Solver/scratch typed tables live in their caller's scope;
// this pool reuses real byte runs without casting them to typed compiler data.
namespace blot_eval_region_arena;
import support.native;
let limit: i64=67108864;
let none: i64=-1;
let large_threshold: i64=4096;
let header_bytes: i64=8;
let block_metadata_bytes: i64=24;
let large_metadata_bytes: i64=40;
struct Costs { large_requested_bytes: i64=0,large_provided_bytes: i64=0,large_fresh_bytes: i64=0,large_reused_bytes: i64=0,large_remap_growth_bytes: i64=0,small_padding_bytes: i64=0 }
struct Stats { requested: i64=0,reused: i64=0,retained_bytes: i64=0,max_capacity: i64=0,oversized_discards: i64=0,discarded_bytes: i64=0,costs: Costs=Costs {} }
struct Meter { requested: i64=0,live: i64=0,peak: i64=0,allocations: i64=0 }
struct Block { next: i64=-1,start: i64=0,capacity: i64=0,used: i64=0 }
struct Large { next: i64=-1,previous: i64=-1,free_next: i64=-1,start: i64=0,capacity: i64=0,bin: i64=0 }
struct Allocation { owner: u64=0,block: i64=-1,start: i64=0,len: i64=0,large: bool=false }
struct Arena { owner_id: u64=0,backing: u64=0,head: i64=-1,tail: i64=-1,current: i64=-1,capacity: i64=0,costs: Costs=Costs {},large: i64=-1,available: i64[64]=[-1;64],solver_meter: Meter=Meter {},scratch_meter: Meter=Meter {} }
reusable[] var byte_storage: u8[>..]=[];
reusable var blocks: Block[>..]=[];
reusable var large_blocks: Large[>..]=[];
reusable var arenas: Arena[>..]=[];
fn add_ok(a: i64,b: i64) -> i64,bool { if a<0||b<0||a>0x7fffffffffffffff-b { return 0,false; } return a+b,true; }
fn aligned(value: i64,alignment: i64) -> i64,bool { let end,ok=add_ok(value,alignment-1); if !ok { return 0,false; } return end&~(alignment-1),true; }
fn power_of_two(value: i64) -> i64,i64,bool { if value<=0 { return 0,0,false; } var capacity: i64=1; var bin=0; while capacity<value { if capacity>0x3fffffffffffffff { return 0,0,false; } capacity*=2; bin++; } return capacity,bin,true; }
fn beginLease(self: Arena&) { self.owner_id=blot_native::fresh_owner_id(); self.costs=Costs {}; self.solver_meter=Meter {}; self.scratch_meter=Meter {}; }
fn solverAllocator(self: Arena&) -> Meter& { return self.solver_meter; }
fn scratchAllocator(self: Arena&) -> Meter& { return self.scratch_meter; }
fn position(block: Block,alignment: i64) -> i64,bool { var a=alignment; if a<header_bytes { a=header_bytes; } let end,ok=add_ok(block_metadata_bytes+block.used,header_bytes); if !ok { return 0,false; } let padded,valid=aligned(block.start+end,a); if !valid { return 0,false; } return padded-block.start-block_metadata_bytes,true; }
fn alloc(self: Arena&,len: i64,alignment: i64) -> Allocation,bool {
 if len<0||alignment<=0||(alignment&(alignment-1))!=0 { return Allocation {},false; } if len>=large_threshold { return allocLarge(self,len,alignment); }
 var cursor=self.current;
 while cursor!=none {
  let block=blocks[cursor]; let start,ok=position(block,alignment); if !ok { return Allocation {},false; }
  if start<=block.capacity&&len<=block.capacity-start { self.costs.small_padding_bytes+=start-block.used; blocks[cursor].used=start+len; self.current=cursor; return Allocation {self.owner_id,cursor,block.start+block_metadata_bytes+start,len,false},true; } cursor=block.next;
 }
 var a=alignment; if a<header_bytes { a=header_bytes; } let needed,ok=add_ok(len,a-1+header_bytes); if !ok { return Allocation {},false; }
 var growth: i64=4096; if self.tail!=none { growth=blocks[self.tail].capacity; if growth>524288 { growth=524288; } growth*=2; } var capacity=needed; if capacity<growth { capacity=growth; }
 let size,valid=add_ok(block_metadata_bytes,capacity); if !valid { return Allocation {},false; } let total,good=add_ok(self.capacity,size); if !good { return Allocation {},false; }
 let memory=byte_storage.alloc_slice(size); let start=byte_storage.index_of(memory[0]); let block=blocks.alloc_index(Block {start:start,capacity:capacity});
 if self.tail!=none { blocks[self.tail].next=block; } else { self.head=block; } self.tail=block; self.current=block; self.capacity=total;
 let offset,position_ok=position(blocks[block],alignment); if !position_ok { return Allocation {},false; } self.costs.small_padding_bytes+=offset; blocks[block].used=offset+len;
 return Allocation {self.owner_id,block,start+block_metadata_bytes+offset,len,false},true;
}
fn allocLarge(self: Arena&,len: i64,alignment: i64) -> Allocation,bool {
 var a=alignment; if a<header_bytes { a=header_bytes; } let overhead,ok=add_ok(large_metadata_bytes+header_bytes,a-1); if !ok { return Allocation {},false; } let needed,good=add_ok(len,overhead); if !good { return Allocation {},false; }
 let capacity,bin,valid=power_of_two(needed); if !valid { return Allocation {},false; } var block=self.available[bin];
 if block!=none { self.available[bin]=large_blocks[block].free_next; self.costs.large_reused_bytes+=large_blocks[block].capacity; }
 else {
  let total,good=add_ok(self.capacity,capacity); if !good { return Allocation {},false; } let memory=byte_storage.alloc_slice(capacity); let start=byte_storage.index_of(memory[0]);
  block=large_blocks.alloc_index(Large {next:self.large,start:start,capacity:capacity,bin:bin}); if self.large!=none { large_blocks[self.large].previous=block; } self.large=block; self.capacity=total; self.costs.large_fresh_bytes+=capacity;
 }
 let start,aligned_ok=aligned(large_blocks[block].start+large_metadata_bytes+header_bytes,a); if !aligned_ok { return Allocation {},false; }
 self.costs.large_requested_bytes+=len; self.costs.large_provided_bytes+=large_blocks[block].capacity; return Allocation {self.owner_id,block,start,len,true},true;
}
fn bytes(self: const Arena&,memory: Allocation) -> u8[:] { assert(memory.owner==self.owner_id); return byte_storage[memory.start..memory.start+memory.len]; }
fn resize(self: Arena&,memory: Allocation,len: i64) -> Allocation,bool {
 if memory.owner!=self.owner_id||len<0 { return memory,false; }
 if memory.large { let block=large_blocks[memory.block]; let offset=memory.start-block.start; if len>block.capacity-offset { return memory,false; } return Allocation {memory.owner,memory.block,memory.start,len,true},true; }
 if self.current!=none {
  let block=blocks[self.current]; let payload=block.start+block_metadata_bytes;
  if memory.start+memory.len==payload+block.used&&memory.start>=payload { let start=memory.start-payload; if len>block.capacity-start { return memory,false; } blocks[self.current].used=start+len; return Allocation {memory.owner,memory.block,memory.start,len,false},true; }
 }
 if len>memory.len { return memory,false; } return Allocation {memory.owner,memory.block,memory.start,len,false},true;
}
fn remap(self: Arena&,memory: Allocation,alignment: i64,len: i64) -> Allocation,bool {
 let resized,ok=resize(self,memory,len); if ok { return resized,true; } if !memory.large||memory.owner!=self.owner_id { return memory,false; }
 let block=large_blocks[memory.block]; if block.capacity<1048576||alignment>8 { return memory,false; }
 let offset=memory.start-block.start; let needed,good=add_ok(len,offset); if !good { return memory,false; } let capacity,bin,valid=power_of_two(needed); if !valid { return memory,false; }
 let total,within=add_ok(self.capacity-block.capacity,capacity); if !within { return memory,false; }
 let moved=byte_storage.realloc_slice(byte_storage[block.start..block.start+block.capacity],capacity); let start=byte_storage.index_of(moved[0]); large_blocks[memory.block].start=start; large_blocks[memory.block].capacity=capacity; large_blocks[memory.block].bin=bin;
 self.capacity=total; self.costs.large_remap_growth_bytes+=capacity-block.capacity; return Allocation {memory.owner,memory.block,start+offset,len,true},true;
}
fn free(self: Arena&,memory: Allocation) {
 assert(memory.owner==self.owner_id);
 if memory.large { let bin=large_blocks[memory.block].bin; large_blocks[memory.block].free_next=self.available[bin]; self.available[bin]=memory.block; return; }
 if self.current!=none { let block=blocks[self.current]; let end=block.start+block_metadata_bytes+block.used; if memory.start+memory.len==end { blocks[self.current].used-=memory.len+header_bytes; } }
}
fn reset(self: Arena&) {
 var cursor=self.head; while cursor!=none { blocks[cursor].used=0; cursor=blocks[cursor].next; } self.current=self.head; self.available=[-1;64];
 var large=self.large; while large!=none { let bin=large_blocks[large].bin; large_blocks[large].free_next=self.available[bin]; self.available[bin]=large; large=large_blocks[large].next; }
}
fn deinit(self: Arena&) {
 var cursor=self.head; while cursor!=none { let block=blocks[cursor]; byte_storage.free_slice(byte_storage[block.start..block.start+block_metadata_bytes+block.capacity]); blocks.free(cursor); cursor=block.next; }
 var large=self.large; while large!=none { let block=large_blocks[large]; byte_storage.free_slice(byte_storage[block.start..block.start+block.capacity]); large_blocks.free(large); large=block.next; }
 self.owner_id=0; self.head=none; self.tail=none; self.current=none; self.large=none; self.capacity=0;
}
struct Pool { owner_id: u64=blot_native::fresh_owner_id(),original: u64,slot: i64=-1,stats: Stats=Stats {} }
fn init(owner: u64) -> Pool { return Pool {original:owner}; }
fn deinit(self: Pool&) { if self.slot!=none { deinit(arenas[self.slot]); arenas.free(self.slot); } self.slot=none; }
fn take(self: Pool&,owner: u64) -> i64 {
 self.stats.requested++;
 if owner!=0&&owner==self.original&&self.slot!=none { let index=self.slot; self.slot=none; self.stats.reused++; self.stats.retained_bytes=0; beginLease(arenas[index]); return index; }
 let index=arenas.alloc_index(Arena {backing:owner}); beginLease(arenas[index]); return index;
}
fn arena(index: i64) -> Arena& { return arenas[index]; }
fn give(self: Pool&,index: i64) {
 let capacity=arenas[index].capacity; if self.stats.max_capacity<capacity { self.stats.max_capacity=capacity; }
 let costs=arenas[index].costs;
 self.stats.costs.large_requested_bytes+=costs.large_requested_bytes; self.stats.costs.large_provided_bytes+=costs.large_provided_bytes; self.stats.costs.large_fresh_bytes+=costs.large_fresh_bytes; self.stats.costs.large_reused_bytes+=costs.large_reused_bytes; self.stats.costs.large_remap_growth_bytes+=costs.large_remap_growth_bytes; self.stats.costs.small_padding_bytes+=costs.small_padding_bytes;
 if arenas[index].backing!=self.original||arenas[index].backing==0||capacity>limit { if capacity>limit { self.stats.oversized_discards++; } self.stats.discarded_bytes+=capacity; deinit(arenas[index]); arenas.free(index); return; }
 if self.slot!=none { if arenas[self.slot].capacity>=capacity { deinit(arenas[index]); arenas.free(index); return; } deinit(arenas[self.slot]); arenas.free(self.slot); }
 reset(arenas[index]); self.slot=index; self.stats.retained_bytes=capacity;
}
