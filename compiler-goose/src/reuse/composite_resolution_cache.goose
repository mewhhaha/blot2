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
struct Entry { root: u32 = 0, at: u32 = 0, stamp: u32 = 0, record: Record=Record {..} }
// Fixed descriptors point only into generation-checked global owner metadata.
struct EntryBuffer { items:Entry[:]=default<Entry[:]>(),len:i64=0 }
reusable[] var entry_runs:Entry[>..]=[];
fn clear(self_:EntryBuffer&) {if self_.items.len!=0 {entry_runs.free_slice(self_.items);}self_.items=default<Entry[:]>();self_.len=0;}
fn restore(self_:EntryBuffer&,values:const Entry[:]) {
 let replacement=entry_runs.alloc_slice(values.len);for value,index in values {replacement[index]=value;}
 clear(self_);self_.items=replacement;self_.len=values.len;
}
fn resize(self_:EntryBuffer&,length:i64) {assert(length>=0&&length<=self_.len);if length==self_.len {return;}restore(self_,self_.items[..length]);}
fn resize(self_:EntryBuffer&,length:i64,value:Entry) {
 assert(length>=0);if length<=self_.len {resize(self_,length);return;}
 let replacement=entry_runs.alloc_slice(length);for old,index in self_.items {replacement[index]=old;}
 for index in self_.len..length {replacement[index]=value;}clear(self_);self_.items=replacement;self_.len=length;
}
struct State {entries:EntryBuffer=EntryBuffer {..},physical: u16=0, effects_physical: u64=0,generation:u32=1,count:u32=0,live:bool=false,owner:u64=0}
reusable var states:State[>..]=[];
var inactive:State=State {..};
struct Cache {entries:EntryBuffer& =inactive.entries,physical: u16& =inactive.physical, effects_physical: u64& =inactive.effects_physical,lease:u32=0,lease_generation:u64=0}
fn initPooled()->Cache,Error {
 if states.len>=0xffffffff {return Cache {..},blot_error::Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=states.alloc_index(State {live:true,owner:generation, ..});let state:State& =states[at];
 return Cache {entries:state.entries,physical:state.physical, effects_physical:state.effects_physical,lease:(at+1) as u32,lease_generation:generation, ..},blot_error::Error.none;
}
fn valid(cache:const Cache&)->bool {return cache.lease!=0&&cache.lease-1<states.len&&states[cache.lease-1].live&&states[cache.lease-1].owner==cache.lease_generation;}
fn deinit(cache:Cache&) {if cache.lease==0 {return;}assert(valid(cache));let at=cache.lease-1;let state:State& =states[at];state.entries.clear();state.live=false;states.free(at);cache=Cache {..};}
fn invalidateState(state: State&, physical: u16, effects_physical: u64) {
    state.physical = physical; state.effects_physical = effects_physical;
    state.count = 0;
    if state.generation == 0xffffffff {
        for &entry in state.entries.items { entry.stamp = 0; entry.root = 0; }
        state.generation = 1;
    } else {
        state.generation += 1;
    }
}
fn activate(cache: Cache&, physical: u16, effects_physical: u64) -> bool {
    assert(valid(cache));
    let state:State& =states[cache.lease-1];
    if physical == 65535 || effects_physical == 18446744073709551615 { return false; }
    if state.physical != physical || state.effects_physical != effects_physical {
        invalidateState(state, physical, effects_physical);
    }
    return true;
}
fn setBase(root: u32, at: u32, sets_mask: i64) -> i64 {
    let h = (root * 2654435769) ^ (at * 2246822507);
    return ((((h ^ (h >> 16)) as i64) & sets_mask) << 2);
}
fn get(cache: const Cache&, root: u32, at: u32) -> blot_support::Option<Record> {
    assert(valid(cache));
    let state:const State& =states[cache.lease-1];
    if state.count == 0 || state.entries.len == 0 { return blot_support::none<Record>(); }
    let gen = state.generation;
    let base = setBase(root, at, (state.entries.len >> 2) - 1);
    for w in 0..4 {
        let entry = state.entries.items[base + w];
        if entry.stamp == gen && entry.root == root && entry.at == at { return blot_support::some(entry.record); }
    }
    return blot_support::none<Record>();
}
fn occupied(cache: const Cache&, root: u32, at: u32) -> bool {
    assert(valid(cache));
    let state:const State& =states[cache.lease-1];
    if state.count == 0 || state.entries.len == 0 { return false; }
    let gen = state.generation;
    let base = setBase(root, at, (state.entries.len >> 2) - 1);
    for w in 0..4 {
        let entry .= state.entries.items[base + w];
        if entry.stamp != gen || entry.root == 0 { return false; }
    }
    return true;
}
fn hasEntries(cache: const Cache&, physical: u16, effects_physical: u64) -> bool {
    if cache.lease == 0 || cache.entries.len == 0 { return false; }
    let state:const State& =states[cache.lease-1];
    return state.count != 0 && state.physical == physical && state.effects_physical == effects_physical;
}
fn probeHit(cache: Cache&, physical: u16, effects_physical: u64, root: u32, at: u32, collision: bool&) -> i64 {
    if cache.lease == 0 || cache.entries.len == 0 || physical == 65535 || effects_physical == 18446744073709551615 { return -1; }
    let state:State& =states[cache.lease-1];
    if state.physical != physical || state.effects_physical != effects_physical {
        invalidateState(state, physical, effects_physical);
        return -1;
    }
    if state.count == 0 { return -1; }
    let gen = state.generation;
    let base = setBase(root, at, (state.entries.len >> 2) - 1);
    var filled: i64 = 0;
    for w in 0..4 {
        let idx = base + w;
        let entry .= state.entries.items[idx];
        if entry.stamp == gen {
            if entry.root == root && entry.at == at { return idx; }
            filled += 1;
        }
    }
    if filled == 4 { collision = true; }
    return -1;
}
fn growEntries(entries: EntryBuffer&, next_len: i64, gen: u32) {
    let replacement = entry_runs.alloc_slice(next_len);
    for &slot in replacement { slot = Entry {..}; }
    let sets_mask = (next_len >> 2) - 1;
    for entry in entries.items {
        if entry.stamp != gen || entry.root == 0 { continue; }
        let base = setBase(entry.root, entry.at, sets_mask);
        var placed = false;
        for w in 0..4 {
            if replacement[base + w].stamp != gen { replacement[base + w] = entry; placed = true; break; }
        }
        if !placed { replacement[base + (((entry.root ^ entry.at) & 3) as i64)] = entry; }
    }
    clear(entries);
    entries.items = replacement;
    entries.len = next_len;
}
fn put(cache: Cache&, root: u32, at: u32, record: Record) -> Error {
    assert(valid(cache));
    let state:State& =states[cache.lease-1];
    if state.entries.len == 0 { state.entries.resize(256, Entry {..}); }
    let gen = state.generation;
    let base = setBase(root, at, (state.entries.len >> 2) - 1);
    var empty: i64 = -1;
    for w in 0..4 {
        let idx = base + w;
        let entry = state.entries.items[idx];
        if entry.stamp == gen {
            if entry.root == root && entry.at == at {
                state.entries.items[idx] = Entry { root, at, gen, record , ..};
                return blot_error::Error.none;
            }
        } else if empty < 0 {
            empty = idx;
        }
    }
    if empty >= 0 {
        state.entries.items[empty] = Entry { root, at, gen, record , ..};
        state.count += 1;
        return blot_error::Error.none;
    }
    if state.entries.len < 2048 {
        growEntries(state.entries, state.entries.len * 2, gen);
        let base2 = setBase(root, at, (state.entries.len >> 2) - 1);
        for w in 0..4 {
            if state.entries.items[base2 + w].stamp != gen {
                state.entries.items[base2 + w] = Entry { root, at, gen, record , ..};
                state.count += 1;
                return blot_error::Error.none;
            }
        }
        state.entries.items[base2 + (((root ^ at) & 3) as i64)] = Entry { root, at, gen, record , ..};
        state.count += 1;
        return blot_error::Error.none;
    }
    state.entries.items[base + (((root ^ at) & 3) as i64)] = Entry { root, at, gen, record , ..};
    return blot_error::Error.none;
}
