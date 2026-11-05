// Source contract: compiler/src/parse/symbols.zig. IDs survive table growth.
namespace blot_parse_symbols;
import support.error;
type Symbol = u32;
let absent: Symbol = 0;
struct Entry { offset: u32, len: u32, hash: u64 }
struct Pool {
 read_only: bool = false, missing_name: bool = false,
 bytes: u8[>..<]&, entries: Entry[>..<]&, buckets: Symbol[>..<]&
}
fn init(bytes: u8[>..<]&,entries: Entry[>..<]&,buckets: Symbol[>..<]&) -> Pool { return Pool {bytes:bytes,entries:entries,buckets:buckets}; }
fn get(pool: const Pool&, symbol: Symbol) -> const u8[:] {
 if symbol == absent { return pool.bytes[..0]; }
 let e = pool.entries[symbol-1]; return pool.bytes[e.offset..e.offset+e.len];
}
fn read_le(text: const u8[:], at: i64, n: i64) -> u64 {
 var value: u64=0; for i in 0..n { value |= (text[at+i] as u64) << (i*8); } return value;
}
fn multiply(a: u64, b: u64) -> u64,u64 {
 let a0=a&0xffffffff; let a1=a>>32; let b0=b&0xffffffff; let b1=b>>32;
 let p00=a0*b0; let p01=a0*b1; let p10=a1*b0;
 let mid=(p00>>32)+(p01&0xffffffff)+(p10&0xffffffff);
 return (mid<<32)|(p00&0xffffffff), a1*b1+(p01>>32)+(p10>>32)+(mid>>32);
}
fn mix(a: u64,b: u64) -> u64 { let low,high=multiply(a,b); return low^high; }
fn wyhash(text: const u8[:]) -> u64 {
 let s0: u64=0xa0761d6478bd642f; let s1: u64=0xe7037ed1a0b428db;
 let s2: u64=0x8ebc6af09c88c6e3; let s3: u64=0x589965cc75374cc3;
 var state=mix(s0,s1); var a: u64=0; var b: u64=0;
 if text.len <= 16 {
  if text.len >= 4 {
   let end=text.len-4; let quarter=(text.len>>3)<<2;
   a=(read_le(text,0,4)<<32)|read_le(text,quarter,4);
   b=(read_le(text,end,4)<<32)|read_le(text,end-quarter,4);
  } else if text.len > 0 { a=(text[0] as u64)<<16|(text[text.len>>1] as u64)<<8|text[text.len-1]; }
 } else {
  var at=0;
  if text.len >= 48 {
   var state1=state; var state2=state;
   while at+48 < text.len {
    state=mix(read_le(text,at,8)^s1,read_le(text,at+8,8)^state);
    state1=mix(read_le(text,at+16,8)^s2,read_le(text,at+24,8)^state1);
    state2=mix(read_le(text,at+32,8)^s3,read_le(text,at+40,8)^state2);
    at+=48;
   }
   state^=state1^state2;
  }
  while at+16 < text.len { state=mix(read_le(text,at,8)^s1,read_le(text,at+8,8)^state); at+=16; }
  a=read_le(text,text.len-16,8); b=read_le(text,text.len-8,8);
 }
 let low,high=multiply(a^s1,b^state);
 return mix(low^s0^(text.len as u64),high^s1);
}
fn find(pool: const Pool&, text: const u8[:], hash: u64) -> Symbol,bool {
 if pool.buckets.len==0 { return absent,false; }
 var slot=(hash & ((pool.buckets.len-1) as u64)) as i64;
 while pool.buckets[slot] != absent {
  let symbol=pool.buckets[slot]; let entry=pool.entries[symbol-1];
  if entry.hash==hash && get(pool,symbol)==text { return symbol,true; }
  slot=(slot+1)&(pool.buckets.len-1);
 }
 return absent,false;
}
fn lookup(pool: const Pool&, text: const u8[:]) -> Symbol,bool { return find(pool,text,wyhash(text)); }
fn reserve_buckets(pool: Pool&, count: i64) -> blot_error::Error {
 if count <= pool.buckets.len/2 { return blot_error::Error.none; }
 var capacity: i64=16;
 if pool.buckets.len != 0 {
  if pool.buckets.len > 0x3fffffffffffffff { return blot_error::Error.symbol_limit; }
  capacity=pool.buckets.len*2;
 }
 var grown: Symbol[>..<]=[]; grown.resize(capacity,absent);
 for entry,index in pool.entries {
  var slot=(entry.hash & ((capacity-1) as u64)) as i64;
  while grown[slot]!=absent { slot=(slot+1)&(capacity-1); }
  grown[slot]=(index+1) as u32;
 }
 pool.buckets.resize(capacity,absent); for symbol,index in grown { pool.buckets[index]=symbol; } return blot_error::Error.none;
}
fn intern(pool: Pool&, text: const u8[:]) -> Symbol,blot_error::Error { return intern_hashed(pool,text,wyhash(text)); }
fn intern_hashed(pool: Pool&, text: const u8[:], hash: u64) -> Symbol,blot_error::Error {
 let existing,found=find(pool,text,hash); if found { return existing,blot_error::Error.none; }
 if pool.read_only { pool.missing_name=true; return absent,blot_error::Error.symbol_limit; }
 if pool.entries.len>=0xffffffff || text.len>0xffffffff || pool.bytes.len>0xffffffff-text.len { return absent,blot_error::Error.symbol_limit; }
 // Copy before growth also covers a substring alias into pool.bytes.
 var stable: u8[>..]=[]; for c in text { stable.push(c); }
 let err=reserve_buckets(pool,pool.entries.len+1); if err!=blot_error::Error.none { return absent,err; }
 let offset=pool.bytes.len as u32;
 for c in stable { pool.bytes.push(c); }
 pool.entries.push(Entry {offset,stable.len as u32,hash});
 let symbol=pool.entries.len as Symbol;
 var slot=(hash & ((pool.buckets.len-1) as u64)) as i64;
 while pool.buckets[slot]!=absent { slot=(slot+1)&(pool.buckets.len-1); }
 pool.buckets[slot]=symbol; return symbol,blot_error::Error.none;
}
