// Source contract: compiler/src/parse/symbols.zig. IDs survive table growth.
namespace blot_parse_symbols;
import support.error;
import support.native;
import support.wyhash;
import support.pooled_buffer;
type Error=blot_error::Error;
type Symbol = u32;
let absent: Symbol = 0;
struct Entry { offset: u32, len: u32, hash: u64 }
struct Bytes { storage: u8[:]=default<u8[:]>(),items: u8[:]=default<u8[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Bytes: u8[>..]=[];
fn ensure(self_: Bytes&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Bytes); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Bytes&,value: u8) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Bytes); self_.len=self_.items.len; }
fn append(self_: Bytes&,values: const u8[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Bytes); self_.len=self_.items.len; }
fn resize(self_: Bytes&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Bytes&,length: i64,value: u8) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Bytes&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Bytes&) { blot_support_pooled_buffer::deinit(self_,pool_Bytes); self_.len=0; self_.failure=blot_error::Error.none; }
struct Entries { storage: Entry[:]=default<Entry[:]>(),items: Entry[:]=default<Entry[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Entries: Entry[>..]=[];
fn ensure(self_: Entries&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Entries); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Entries&,value: Entry) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Entries); self_.len=self_.items.len; }
fn append(self_: Entries&,values: const Entry[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Entries); self_.len=self_.items.len; }
fn resize(self_: Entries&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Entries&,length: i64,value: Entry) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Entries&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Entries&) { blot_support_pooled_buffer::deinit(self_,pool_Entries); self_.len=0; self_.failure=blot_error::Error.none; }
struct Buckets { storage: Symbol[:]=default<Symbol[:]>(),items: Symbol[:]=default<Symbol[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Buckets: Symbol[>..]=[];
fn ensure(self_: Buckets&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Buckets); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Buckets&,value: Symbol) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Buckets); self_.len=self_.items.len; }
fn append(self_: Buckets&,values: const Symbol[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Buckets); self_.len=self_.items.len; }
fn resize(self_: Buckets&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Buckets&,length: i64,value: Symbol) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Buckets&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Buckets&) { blot_support_pooled_buffer::deinit(self_,pool_Buckets); self_.len=0; self_.failure=blot_error::Error.none; }
struct State { outside_view:bool=false,bytes: Bytes=Bytes {},entries: Entries=Entries {},buckets: Buckets=Buckets {},generation: u64=0,owner_id: u64=0,live: bool=false }
reusable var states: State[>..]=[];
var inactive: State=State {};
var next_generation: u64=1;
struct Pool { visible:i64=0x7fffffffffffffff,read_only: bool=false,missing_name: bool=false,owner_id: u64=0,bytes: Bytes& =inactive.bytes,entries: Entries& =inactive.entries,buckets: Buckets& =inactive.buckets,lease: u32=0,generation: u64=0 }
fn initPooled() -> Pool,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Pool {},blot_error::Error.out_of_memory; } let generation=next_generation; next_generation++; let owner=blot_native::fresh_owner_id(); let at=states.alloc_index(State {generation:generation,owner_id:owner,live:true}); let state: State& =states[at]; return Pool {owner_id:owner,bytes:state.bytes,entries:state.entries,buckets:state.buckets,lease:(at+1) as u32,generation:generation},blot_error::Error.none; }
fn valid(pool: const Pool&) -> bool { return pool.lease!=0&&pool.lease-1<states.len&&states[pool.lease-1].live&&states[pool.lease-1].generation==pool.generation&&states[pool.lease-1].owner_id==pool.owner_id; }
// Resolve an existing live header without retaining or copying its storage.
fn canonical(pool:const Pool&)->Pool {
 assert(valid(pool));let state:State& =states[pool.lease-1];
 assert(pool.bytes .== state.bytes && pool.entries .== state.entries && pool.buckets .== state.buckets);
 return Pool{visible:pool.visible,read_only:pool.read_only,missing_name:pool.missing_name,owner_id:pool.owner_id,bytes:state.bytes,entries:state.entries,buckets:state.buckets,lease:pool.lease,generation:pool.generation};
}
fn deinit(pool: Pool&) { if pool.lease==0 { return; } assert(!pool.read_only&&valid(pool)); pool.bytes.deinit(); pool.entries.deinit(); pool.buckets.deinit(); let at=pool.lease-1; states[at].live=false; states.free(at); pool=Pool {}; }
fn get(pool: const Pool&, symbol: Symbol) -> const u8[:] {
 if symbol == absent { return pool.bytes.items[..0]; }
 if symbol>pool.visible {states[pool.lease-1].outside_view=true;}
 let e = pool.entries.items[symbol-1]; return pool.bytes.items[e.offset..e.offset+e.len];
}
fn restrictView(pool:Pool&,end:i64) {
 assert(pool.read_only);
 pool.visible=end;
 states[pool.lease-1].outside_view=false;
}
fn outsideView(pool:const Pool&)->bool {return states[pool.lease-1].outside_view;}
fn wyhash(text: const u8[:]) -> u64 { return blot_support_wyhash::hash(0,text); }
fn find(pool: const Pool&, text: const u8[:], hash: u64) -> Symbol,bool {
 let items = pool.buckets.items;
 if items.len==0 { return absent,false; }
 let entries = pool.entries.items;
 let bytes = pool.bytes.items;
 let mask = items.len-1;
 var slot=(hash & (mask as u64)) as i64;
 while items[slot] != absent {
  let symbol=items[slot]; let entry=entries[symbol-1];
  if symbol<=pool.visible && entry.hash==hash && (entry.len as i64)==text.len && bytes[entry.offset..entry.offset+entry.len]==text { return symbol,true; }
  slot=(slot+1)&mask;
 }
 return absent,false;
}
fn lookup(pool: const Pool&, text: const u8[:]) -> Symbol,bool { return find(pool,text,wyhash(text)); }
let zero_buckets: Symbol[64] = [0; 64];
fn zeroBuckets(slice: Symbol[:]) {
 var off: i64 = 0;
 while off + 64 <= slice.len {
  slice[off..off+64].move_from(zero_buckets[..]);
  off += 64;
 }
 if off < slice.len { slice[off..].move_from(zero_buckets[..slice.len-off]); }
}
fn reserve_buckets(pool: Pool&,count: i64) -> Error {
 if count<=pool.buckets.len/2 { return blot_error::Error.none; }
 var capacity: i64=16;
 if pool.buckets.len!=0 { capacity=pool.buckets.len; }
 while count>capacity/2 {
  if capacity>0x3fffffffffffffff { return blot_error::Error.symbol_limit; }
  capacity=capacity*2;
 }
 let grown=pool_Buckets.alloc_slice(capacity);
 zeroBuckets(grown);
 let mask = capacity-1;
 for entry,index in pool.entries.items {
  var slot=(entry.hash&(mask as u64)) as i64;
  while grown[slot]!=absent { slot=(slot+1)&mask; }
  grown[slot]=(index+1) as u32;
 }
 pool.buckets.deinit(); pool.buckets.storage=grown; pool.buckets.items=grown; pool.buckets.len=capacity;
 return blot_error::Error.none;
}
fn reserve(pool: Pool&, count: i64, byte_hint: i64) -> Error {
 assert(valid(pool));
 if count > 0 {
  let e_err = pool.entries.ensure(count);
  if e_err != blot_error::Error.none { return e_err; }
  let b_err = reserve_buckets(pool, count);
  if b_err != blot_error::Error.none { return b_err; }
 }
 if byte_hint > 0 {
  let s_err = pool.bytes.ensure(byte_hint);
  if s_err != blot_error::Error.none { return s_err; }
 }
 return blot_error::Error.none;
}
// Append known-unique symbols `src[start..end]` directly at `dest.entries.len == start`.
fn appendUniqueSlice(dest: Pool&, src: const Pool&, start: i64, end: i64) -> Error {
 assert(valid(dest));
 if end <= start { return blot_error::Error.none; }
 assert(dest.entries.len == start && end <= src.entries.len);
 if dest.read_only { dest.missing_name = true; return blot_error::Error.symbol_limit; }
 let src_entries = src.entries.items;
 let byte_start = src_entries[start].offset as i64;
 let last = src_entries[end - 1];
 let byte_end = (last.offset as i64) + (last.len as i64);
 let byte_count = byte_end - byte_start;
 if end > 0xffffffff || dest.bytes.len > 0xffffffff - byte_count { return blot_error::Error.symbol_limit; }
 let err = reserve(dest, end, dest.bytes.len + byte_count);
 if err != blot_error::Error.none { return err; }
 let delta = dest.bytes.len - byte_start;
 if byte_count > 0 { dest.bytes.append(src.bytes.items[byte_start..byte_end]); }
 if dest.bytes.failure != blot_error::Error.none { return dest.bytes.failure; }
 let buckets = dest.buckets.items;
 let mask = buckets.len - 1;
 for i in start..end {
  let e = src_entries[i];
  dest.entries.push(Entry { ((e.offset as i64) + delta) as u32, e.len, e.hash });
  let symbol = (i + 1) as Symbol;
  var slot = (e.hash & (mask as u64)) as i64;
  while buckets[slot] != absent { slot = (slot + 1) & mask; }
  buckets[slot] = symbol;
 }
 return dest.entries.failure;
}
fn intern(pool: Pool&, text: const u8[:]) -> Symbol,blot_error::Error { return intern_hashed(pool,text,wyhash(text)); }
reusable[] var intern_bytes: u8[>..]=[];
fn intern_hashed(pool: Pool&,text: const u8[:],hash: u64) -> Symbol,Error {
 assert(valid(pool)); let existing,found=find(pool,text,hash); if found { return existing,blot_error::Error.none; }
 if pool.read_only { pool.missing_name=true; return absent,blot_error::Error.symbol_limit; }
 if pool.entries.len>=0xffffffff||text.len>0xffffffff||pool.bytes.len>0xffffffff-text.len { return absent,blot_error::Error.symbol_limit; }
 let entries_error=pool.entries.ensure(pool.entries.len+1); if entries_error!=blot_error::Error.none { return absent,entries_error; }
 let buckets_error=reserve_buckets(pool,pool.entries.len+1); if buckets_error!=blot_error::Error.none { return absent,buckets_error; }
 let offset=pool.bytes.len as u32;
 if pool.bytes.len+text.len<=pool.bytes.storage.len {
  pool.bytes.append(text);
 } else if text.len<=256 {
  var stack_buf:u8[256]=[0;256];
  if text.len!=0 { stack_buf[..text.len].move_from(text); }
  let bytes_error=pool.bytes.ensure(pool.bytes.len+text.len); if bytes_error!=blot_error::Error.none { return absent,bytes_error; }
  pool.bytes.append(stack_buf[..text.len]);
 } else {
  // A typed temporary preserves self-substring inputs across capacity growth.
  let stable=intern_bytes.alloc_slice(text.len); stable.move_from(text);
  let bytes_error=pool.bytes.ensure(pool.bytes.len+stable.len); if bytes_error!=blot_error::Error.none { intern_bytes.free_slice(stable); return absent,bytes_error; }
  pool.bytes.append(stable); intern_bytes.free_slice(stable);
 }
 pool.entries.push(Entry {offset,text.len as u32,hash});
 let symbol=pool.entries.len as Symbol; var slot=(hash&((pool.buckets.len-1) as u64)) as i64; while pool.buckets.items[slot]!=absent { slot=(slot+1)&(pool.buckets.len-1); } pool.buckets.items[slot]=symbol; return symbol,blot_error::Error.none;
}
