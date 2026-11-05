namespace blot_reuse_composite_resolution_cache;
import support.error;
import support.option;
import support.native;

type Error = blot_error::Error;
struct Dependency { variable: u32=0, last: u32=0, effect: bool = false }
struct Record {
    result: u32 = 0, dependencies: Dependency[8]=[Dependency {..};8], count: u8 = 0,
    future_clock: blot_support::Option<u32>,
}
fn add(record: Record&, dependency: Dependency) -> bool {
    for index in record.count {
        let prior = record.dependencies[index];
        if prior.variable == dependency.variable && prior.effect == dependency.effect { return true; }
    }
    if record.count == 8 { return false; }
    record.dependencies[record.count] = dependency; record.count++;
    return true;
}
struct Entry { root: u32 = 0, at: u32 = 0, record: Record=Record {..} }
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
struct State {entries:EntryBuffer=EntryBuffer {..},physical: u16=0, effects_physical: u64=0,live:bool=false,owner:u64=0}
reusable var states:State[>..]=[];
var inactive:State=State {..};
struct Cache {entries:EntryBuffer&=inactive.entries,physical: u16&=inactive.physical, effects_physical: u64&=inactive.effects_physical,lease:u32=0,lease_generation:u64=0}
fn initPooled()->Cache,Error {
 if states.len>=0xffffffff {return Cache {..},Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=states.alloc_index(State {live:true,owner:generation, ..});let state:State&=states[at];
 return Cache {entries:state.entries,physical:state.physical, effects_physical:state.effects_physical,lease:(at+1) as u32,lease_generation:generation, ..},Error.none;
}
fn valid(cache:const Cache&)->bool {return cache.lease!=0&&cache.lease-1<states.len&&states[cache.lease-1].live&&states[cache.lease-1].owner==cache.lease_generation;}
fn deinit(cache:Cache&) {if cache.lease==0 {return;}assert(valid(cache));cache.entries.clear();let at=cache.lease-1;states[at].live=false;states.free(at);cache=Cache {..};}
fn activate(cache: Cache&, physical: u16, effects_physical: u64) -> bool {
    assert(valid(cache));
    if physical == 65535 || effects_physical == 18446744073709551615 { return false; }
    if cache.physical != physical || cache.effects_physical != effects_physical {
        for &entry in cache.entries.items { entry.root = 0; }
        cache.physical = physical; cache.effects_physical = effects_physical;
    }
    return true;
}
fn slot(root: u32, at: u32) -> i64 { ((root * 2654435769 ^ at * 2246822507) >> 28) as i64 }
fn get(cache: const Cache&, root: u32, at: u32) -> blot_support::Option<Record> {
    assert(valid(cache));
    if cache.entries.len == 0 { return blot_support::none<Record>(); }
    let entry = cache.entries.items[slot(root, at)];
    if entry.root == root && entry.at == at { return blot_support::some(entry.record); }
    return blot_support::none<Record>();
}
fn occupied(cache: const Cache&, root: u32, at: u32) -> bool {
    assert(valid(cache));
    cache.entries.len != 0 && cache.entries.items[slot(root, at)].root != 0
}
fn put(cache: Cache&, root: u32, at: u32, record: Record) -> Error {
    assert(valid(cache));
    if cache.entries.len == 0 { cache.entries.resize(16, Entry {..}); }
    cache.entries.items[slot(root, at)] = Entry { root, at, record , ..};
    return Error.none;
}
