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
struct Allocation { owner: u64=0,block_: i64=-1,start: i64=0,len: i64=0,large: bool=false }
struct Arena { owner_id: u64=0,backing: u64=0,head: i64=-1,tail: i64=-1,current: i64=-1,capacity: i64=0,costs: Costs=Costs {},large: i64=-1,available: i64[64]=[-1;64],solver_meter: Meter=Meter {},scratch_meter: Meter=Meter {} }
reusable[] var byte_storage: u8[>..]=[];
reusable var blocks: Block[>..]=[];
reusable var large_blocks: Large[>..]=[];
reusable var arenas: Arena[>..]=[];
fn add_ok(a: i64,b: i64) -> i64,bool { if a<0||b<0||a>0x7fffffffffffffff-b { return 0,false; } return a+b,true; }
fn aligned(value: i64,alignment: i64) -> i64,bool { let end,ok=add_ok(value,alignment-1); if !ok { return 0,false; } return end&~(alignment-1),true; }
fn power_of_two(value: i64) -> i64,i64,bool { if value<=0 { return 0,0,false; } var capacity: i64=1; var bin=0; while capacity<value { if capacity>0x3fffffffffffffff { return 0,0,false; } capacity*=2; bin++; } return capacity,bin,true; }
fn beginLease(self_: Arena&) { self_.owner_id=blot_native::fresh_owner_id(); self_.costs=Costs {}; self_.solver_meter=Meter {}; self_.scratch_meter=Meter {}; }
fn solverAllocator(self_: Arena&) -> Meter& { return self_.solver_meter; }
fn scratchAllocator(self_: Arena&) -> Meter& { return self_.scratch_meter; }
fn position(block_: Block,alignment: i64) -> i64,bool { var a=alignment; if a<header_bytes { a=header_bytes; } let end,ok=add_ok(block_metadata_bytes+block_.used,header_bytes); if !ok { return 0,false; } let padded,valid=aligned(block_.start+end,a); if !valid { return 0,false; } return padded-block_.start-block_metadata_bytes,true; }
fn alloc(self_: Arena&,len: i64,alignment: i64) -> Allocation,bool {
 if len<0||alignment<=0||(alignment&(alignment-1))!=0 { return Allocation {},false; } if len>=large_threshold { return allocLarge(self_,len,alignment); }
 var cursor=self_.current;
 while cursor!=none {
  let block_=blocks[cursor]; let start,ok=position(block_,alignment); if !ok { return Allocation {},false; }
  if start<=block_.capacity&&len<=block_.capacity-start { self_.costs.small_padding_bytes+=start-block_.used; blocks[cursor].used=start+len; self_.current=cursor; return Allocation {self_.owner_id,cursor,block_.start+block_metadata_bytes+start,len,false},true; } cursor=block_.next;
 }
 var a=alignment; if a<header_bytes { a=header_bytes; } let needed,ok=add_ok(len,a-1+header_bytes); if !ok { return Allocation {},false; }
 var growth: i64=4096; if self_.tail!=none { growth=blocks[self_.tail].capacity; if growth>524288 { growth=524288; } growth*=2; } var capacity=needed; if capacity<growth { capacity=growth; }
 let size,valid=add_ok(block_metadata_bytes,capacity); if !valid { return Allocation {},false; } let total,good=add_ok(self_.capacity,size); if !good { return Allocation {},false; }
 let memory=byte_storage.alloc_slice(size); let start=byte_storage.index_of(memory[0]); let block_=blocks.alloc_index(Block {start:start,capacity:capacity});
 if self_.tail!=none { blocks[self_.tail].next=block_; } else { self_.head=block_; } self_.tail=block_; self_.current=block_; self_.capacity=total;
 let offset,position_ok=position(blocks[block_],alignment); if !position_ok { return Allocation {},false; } self_.costs.small_padding_bytes+=offset; blocks[block_].used=offset+len;
 return Allocation {self_.owner_id,block_,start+block_metadata_bytes+offset,len,false},true;
}
fn allocLarge(self_: Arena&,len: i64,alignment: i64) -> Allocation,bool {
 var a=alignment; if a<header_bytes { a=header_bytes; } let overhead,ok=add_ok(large_metadata_bytes+header_bytes,a-1); if !ok { return Allocation {},false; } let needed,good=add_ok(len,overhead); if !good { return Allocation {},false; }
 let capacity,bin,valid=power_of_two(needed); if !valid { return Allocation {},false; } var block_=self_.available[bin];
 if block_!=none { self_.available[bin]=large_blocks[block_].free_next; self_.costs.large_reused_bytes+=large_blocks[block_].capacity; }
 else {
  let total,good=add_ok(self_.capacity,capacity); if !good { return Allocation {},false; } let memory=byte_storage.alloc_slice(capacity); let start=byte_storage.index_of(memory[0]);
  block_=large_blocks.alloc_index(Large {next:self_.large,start:start,capacity:capacity,bin:bin}); if self_.large!=none { large_blocks[self_.large].previous=block_; } self_.large=block_; self_.capacity=total; self_.costs.large_fresh_bytes+=capacity;
 }
 let start,aligned_ok=aligned(large_blocks[block_].start+large_metadata_bytes+header_bytes,a); if !aligned_ok { return Allocation {},false; }
 self_.costs.large_requested_bytes+=len; self_.costs.large_provided_bytes+=large_blocks[block_].capacity; return Allocation {self_.owner_id,block_,start,len,true},true;
}
fn bytes(self_: const Arena&,memory: Allocation) -> u8[:] { assert(memory.owner==self_.owner_id); return byte_storage[memory.start..memory.start+memory.len]; }
fn resize(self_: Arena&,memory: Allocation,len: i64) -> Allocation,bool {
 if memory.owner!=self_.owner_id||len<0 { return memory,false; }
 if memory.large { let block_=large_blocks[memory.block_]; let offset=memory.start-block_.start; if len>block_.capacity-offset { return memory,false; } return Allocation {memory.owner,memory.block_,memory.start,len,true},true; }
 if self_.current!=none {
  let block_=blocks[self_.current]; let payload=block_.start+block_metadata_bytes;
  if memory.start+memory.len==payload+block_.used&&memory.start>=payload { let start=memory.start-payload; if len>block_.capacity-start { return memory,false; } blocks[self_.current].used=start+len; return Allocation {memory.owner,memory.block_,memory.start,len,false},true; }
 }
 if len>memory.len { return memory,false; } return Allocation {memory.owner,memory.block_,memory.start,len,false},true;
}
fn remap(self_: Arena&,memory: Allocation,alignment: i64,len: i64) -> Allocation,bool {
 let resized,ok=resize(self_,memory,len); if ok { return resized,true; } if !memory.large||memory.owner!=self_.owner_id { return memory,false; }
 let block_=large_blocks[memory.block_]; if block_.capacity<1048576||alignment>8 { return memory,false; }
 let offset=memory.start-block_.start; let needed,good=add_ok(len,offset); if !good { return memory,false; } let capacity,bin,valid=power_of_two(needed); if !valid { return memory,false; }
 let total,within=add_ok(self_.capacity-block_.capacity,capacity); if !within { return memory,false; }
 let moved=byte_storage.realloc_slice(byte_storage[block_.start..block_.start+block_.capacity],capacity); let start=byte_storage.index_of(moved[0]); large_blocks[memory.block_].start=start; large_blocks[memory.block_].capacity=capacity; large_blocks[memory.block_].bin=bin;
 self_.capacity=total; self_.costs.large_remap_growth_bytes+=capacity-block_.capacity; return Allocation {memory.owner,memory.block_,start+offset,len,true},true;
}
fn free(self_: Arena&,memory: Allocation) {
 assert(memory.owner==self_.owner_id);
 if memory.large { let bin=large_blocks[memory.block_].bin; large_blocks[memory.block_].free_next=self_.available[bin]; self_.available[bin]=memory.block_; return; }
 if self_.current!=none { let block_=blocks[self_.current]; let end=block_.start+block_metadata_bytes+block_.used; if memory.start+memory.len==end { blocks[self_.current].used-=memory.len+header_bytes; } }
}
fn reset(self_: Arena&) {
 var cursor=self_.head; while cursor!=none { blocks[cursor].used=0; cursor=blocks[cursor].next; } self_.current=self_.head; self_.available=[-1;64];
 var large=self_.large; while large!=none { let bin=large_blocks[large].bin; large_blocks[large].free_next=self_.available[bin]; self_.available[bin]=large; large=large_blocks[large].next; }
}
fn deinit(self_: Arena&) {
 var cursor=self_.head; while cursor!=none { let block_=blocks[cursor]; byte_storage.free_slice(byte_storage[block_.start..block_.start+block_metadata_bytes+block_.capacity]); blocks.free(cursor); cursor=block_.next; }
 var large=self_.large; while large!=none { let block_=large_blocks[large]; byte_storage.free_slice(byte_storage[block_.start..block_.start+block_.capacity]); large_blocks.free(large); large=block_.next; }
 self_.owner_id=0; self_.head=none; self_.tail=none; self_.current=none; self_.large=none; self_.capacity=0;
}
struct Pool { owner_id: u64=blot_native::fresh_owner_id(),original: u64,slot: i64=-1,stats: Stats=Stats {} }
fn init(owner: u64) -> Pool { return Pool {original:owner}; }
fn deinit(self_: Pool&) { if self_.slot!=none { deinit(arenas[self_.slot]); arenas.free(self_.slot); } self_.slot=none; }
fn take(self_: Pool&,owner: u64) -> i64 {
 self_.stats.requested++;
 if owner!=0&&owner==self_.original&&self_.slot!=none { let index=self_.slot; self_.slot=none; self_.stats.reused++; self_.stats.retained_bytes=0; beginLease(arenas[index]); return index; }
 let index=arenas.alloc_index(Arena {backing:owner}); beginLease(arenas[index]); return index;
}
fn arena(index: i64) -> Arena& { return arenas[index]; }
fn give(self_: Pool&,index: i64) {
 let capacity=arenas[index].capacity; if self_.stats.max_capacity<capacity { self_.stats.max_capacity=capacity; }
 let costs=arenas[index].costs;
 self_.stats.costs.large_requested_bytes+=costs.large_requested_bytes; self_.stats.costs.large_provided_bytes+=costs.large_provided_bytes; self_.stats.costs.large_fresh_bytes+=costs.large_fresh_bytes; self_.stats.costs.large_reused_bytes+=costs.large_reused_bytes; self_.stats.costs.large_remap_growth_bytes+=costs.large_remap_growth_bytes; self_.stats.costs.small_padding_bytes+=costs.small_padding_bytes;
 if arenas[index].backing!=self_.original||arenas[index].backing==0||capacity>limit { if capacity>limit { self_.stats.oversized_discards++; } self_.stats.discarded_bytes+=capacity; deinit(arenas[index]); arenas.free(index); return; }
 if self_.slot!=none { if arenas[self_.slot].capacity>=capacity { deinit(arenas[index]); arenas.free(index); return; } deinit(arenas[self_.slot]); arenas.free(self_.slot); }
 reset(arenas[index]); self_.slot=index; self_.stats.retained_bytes=capacity;
}
