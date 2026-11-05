namespace blot_reuse_epoch_resolution_cache;
import std;
import support.error;
import support.option;
import support.native;

type Error = blot_error::Error;
struct Entry { generation: u32 = 0, root: u32 = 0, result: u32 = 0 }
// Fixed descriptors point only into generation-checked global owner metadata.
struct EntryBuffer { items:Entry[:]=[],len:i64=0 }
reusable[] var entry_runs:Entry[>..]=[];
fn clear(self:EntryBuffer&) {if self.items.len!=0 {entry_runs.free_slice(self.items);}self.items=[];self.len=0;}
fn restore(self:EntryBuffer&,values:const Entry[:]) {
 let replacement=entry_runs.alloc_slice(values.len);for value,index in values {replacement[index]=value;}
 clear(self);self.items=replacement;self.len=values.len;
}
fn resize(self:EntryBuffer&,length:i64) {assert(length>=0&&length<=self.len);if length==self.len {return;}restore(self,self.items[..length]);}
fn resize(self:EntryBuffer&,length:i64,value:Entry) {
 assert(length>=0);if length<=self.len {resize(self,length);return;}
 let replacement=entry_runs.alloc_slice(length);for old,index in self.items {replacement[index]=old;}
 for index in self.len..length {replacement[index]=value;}clear(self);self.items=replacement;self.len=length;
}
struct State {entries:EntryBuffer=EntryBuffer {},generation: u32=0, mutation: u32=0, other: u32=0, count: i64=0, high_water: i64=0,live:bool=false,owner:u64=0}
reusable var states:State[>..]=[];
var inactive:State=State {};
struct Cache {entries:EntryBuffer&=inactive.entries,generation: u32&=inactive.generation, mutation: u32&=inactive.mutation, other: u32&=inactive.other, count: i64&=inactive.count, high_water: i64&=inactive.high_water,lease:u32=0,lease_generation:u64=0}
fn initPooled()->Cache,Error {
 if states.len>=0xffffffff {return Cache {},Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=states.alloc_index(State {live:true,owner:generation});let state:State&=states[at];
 return Cache {entries:state.entries,generation:state.generation, mutation:state.mutation, other:state.other, count:state.count, high_water:state.high_water,lease:(at+1) as u32,lease_generation:generation},Error.none;
}
fn valid(cache:const Cache&)->bool {return cache.lease!=0&&cache.lease-1<states.len&&states[cache.lease-1].live&&states[cache.lease-1].owner==cache.lease_generation;}
fn deinit(cache:Cache&) {if cache.lease==0 {return;}assert(valid(cache));cache.entries.clear();let at=cache.lease-1;states[at].live=false;states.free(at);cache=Cache {};}
fn activate(cache: Cache&, mutation: u32, other: u32) -> bool {
    assert(valid(cache));
    if cache.generation == 4294967295 { return false; }
    if cache.generation != 0 && cache.mutation == mutation && cache.other == other { return true; }
    cache.generation++; cache.mutation = mutation; cache.other = other; cache.count = 0;
    return cache.generation != 4294967295;
}
fn index(root: u32, mask: i64) -> i64 {
    var mixed = root;
    mixed ^= mixed >> 16; mixed *= 2146121005;
    mixed ^= mixed >> 15; mixed *= 2221713035;
    mixed ^= mixed >> 16;
    return mixed as i64 & mask;
}
fn get(cache: const Cache&, root: u32) -> blot_support::Option<u32> {
    assert(valid(cache));
    if cache.entries.len == 0 { return blot_support::none<u32>(); }
    var slot = index(root, cache.entries.len - 1);
    loop {
        let entry = cache.entries.items[slot];
        if entry.generation != cache.generation { return blot_support::none<u32>(); }
        if entry.root == root { return blot_support::some(entry.result); }
        slot = (slot + 1) & (cache.entries.len - 1);
    }
}
fn place(entries: Entry[:], entry: Entry) {
    var slot = index(entry.root, entries.len - 1);
    while entries[slot].generation == entry.generation { slot = (slot + 1) & (entries.len - 1); }
    entries[slot] = entry;
}
fn grow(cache:Cache&)->Error {
 var capacity:i64=8;if cache.entries.len!=0 {if cache.entries.len>0x3fffffffffffffff {return Error.out_of_memory;}capacity=cache.entries.len*2;}
 let replacement=entry_runs.alloc_slice(capacity);for &entry in replacement {entry=Entry {};}
 for entry in cache.entries.items {if entry.generation==cache.generation {place(replacement,entry);}}
 cache.entries.clear();cache.entries.items=replacement;cache.entries.len=capacity;return Error.none;
}
fn put(cache: Cache&, root: u32, result: u32) -> Error {
    assert(valid(cache));
    if cache.generation == 0 || cache.generation == 4294967295 { abort("inactive resolution cache"); }
    if cache.entries.len == 0 {
        let error = grow(cache); if error != Error.none { return error; }
    }
    var slot = index(root, cache.entries.len - 1);
    while cache.entries.items[slot].generation == cache.generation {
        if cache.entries.items[slot].root == root { cache.entries.items[slot].result = result; return Error.none; }
        slot = (slot + 1) & (cache.entries.len - 1);
    }
    if cache.count >= cache.entries.len - cache.entries.len / 4 {
        let error = grow(cache); if error != Error.none { return error; }
        slot = index(root, cache.entries.len - 1);
        while cache.entries.items[slot].generation == cache.generation { slot = (slot + 1) & (cache.entries.len - 1); }
    }
    cache.entries.items[slot] = Entry { cache.generation, root, result };
    cache.count++; cache.high_water = max(cache.high_water, root as i64 + 1);
    return Error.none;
}
