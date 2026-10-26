// Private source-backed experiment: all pool, owner, builder, domain, and
// view state is local to this invocation. No externally supplied ID is used
// as authority. This is neither generated Wasm nor a public bridge.
namespace viewalloc_run;
import viewalloc_verify;
import viewcall_core;
import pool;
import builder;
struct Result {status:i64=4,value:u32=0,detail:i64=0,clean:bool=false}
fn term(id:i64,index:u32,middle:u32,len:u32)->u32 {if id==1 {return index;}if id==2 {return middle;}return len;}
fn run(src:u8[:],prefix:viewcall_core::Program&,backing_available:bool)->Result {
 let plan=viewalloc_verify::check(src,prefix);if plan.status!=0 {return Result {status:4};}
 var slots:pool::Slot[1]=[pool::Slot {}];var bits:u32[1]=[0];var memory:u8[8192]=[0;8192];
 let granules:u32=if backing_available {1} else {0};let nbits=if backing_available {1} else {0};
 let reserved=pool::reserve(slots,bits[..nbits],4096,granules,plan.reserve);
 if reserved.status!=0 {return Result {status:1,detail:reserved.status,clean:slots[0].state==0 && bits[0]==0};}
 let allocated=pool::try_alloc(slots,bits[..nbits],4096,granules,reserved.slot,reserved.generation,4,1);
 if allocated.status!=0 {let closed=pool::close(slots,bits[..nbits],4096,granules,reserved.slot,reserved.generation);if !closed {return Result {status:3};}return Result {status:2,detail:allocated.status,clean:slots[0].state==0 && bits[0]==0};}
 var clock=builder::Clock {};var cell=builder::Cell {};let begin=builder::begin(cell,clock,memory,allocated.data,1,1,1);
 if begin.status!=0 {let _=pool::close(slots,bits[..nbits],4096,granules,reserved.slot,reserved.generation);return Result {status:3,detail:begin.status};}
 var bytes:u8[4]=[0;4];for k in 4 {bytes[k]=(plan.value >> (8*k) & 255) as u8;}
 let appended=builder::try_append(cell,begin.handle,memory,bytes);
 if appended.status!=0 {let _=builder::discard(cell,begin.handle);let _=pool::close(slots,bits[..nbits],4096,granules,reserved.slot,reserved.generation);return Result {status:3,detail:appended.status};}
 var frozen=builder::freeze(cell,appended.handle,clock,memory);
 if frozen.status!=0 {let _=builder::discard(cell,appended.handle);let _=pool::close(slots,bits[..nbits],4096,granules,reserved.slot,reserved.generation);return Result {status:3,detail:frozen.status};}
 // The lexical open supplies a fresh domain and loan of this exact frozen
 // allocation. The checked source contains no writes while it is active.
 var take=true;for g in prefix.callee.guards {let l=term(g.left,plan.index,plan.middle,frozen.length);let r=term(g.right,plan.index,plan.middle,frozen.length);if !(if g.strict {l<r} else {l<=r}) {take=false;break;}}
 var result=prefix.callee.fallback;
 if take {
  // Source proof, exact fresh view length, initialized prefix, and the
  // allocation range establish this access. No runtime object-bounds guard.
  let pos=frozen.data+plan.index*4;
  result=memory[pos] as u32 | (memory[pos+1] as u32 << 8) | (memory[pos+2] as u32 << 16) | (memory[pos+3] as u32 << 24);
 }
 // End the only View descriptor before ending Space and closing the owner.
 frozen=builder::Frozen {};let closed=pool::close(slots,bits[..nbits],4096,granules,reserved.slot,reserved.generation);
 if !closed {return Result {status:3};}return Result {status:0,value:result,clean:slots[0].state==0 && bits[0]==0};
}
