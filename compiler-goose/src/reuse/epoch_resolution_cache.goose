namespace blot_reuse_epoch_resolution_cache;
import std;
import support.error;
import support.option;

type Error = blot_error::Error;
struct Entry { generation: u32 = 0, root: u32 = 0, result: u32 = 0 }
struct Cache {
    entries: Entry[>..<]&,
    generation: u32 = 0, mutation: u32 = 0, other: u32 = 0,
    count: i64 = 0, high_water: i64 = 0,
}
fn init(entries: Entry[>..<]&) -> Cache { Cache { entries } }
fn deinit(cache: Cache&) {
    cache.entries.clear(); cache.generation = 0; cache.count = 0;
    cache.high_water = 0; cache.mutation = 0; cache.other = 0;
}
fn activate(cache: Cache&, mutation: u32, other: u32) -> bool {
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
fn get(cache: Cache&, root: u32) -> blot_support::Option<u32> {
    if cache.entries.len == 0 { return blot_support::none<u32>(); }
    var slot = index(root, cache.entries.len - 1);
    loop {
        let entry = cache.entries[slot];
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
fn grow(cache: Cache&) -> Error {
    var capacity: i64 = 8;
    if cache.entries.len != 0 {
        if cache.entries.len > 4611686018427387903 { return Error.out_of_memory; }
        capacity = cache.entries.len * 2;
    }
    var previous: Entry[>..] = [];
    for entry in cache.entries {
        if entry.generation == cache.generation { previous.push(entry); }
    }
    cache.entries.resize(capacity, Entry {});
    for &entry in cache.entries { entry = Entry {}; }
    for entry in previous { place(cache.entries, entry); }
    return Error.none;
}
fn put(cache: Cache&, root: u32, result: u32) -> Error {
    if cache.generation == 0 || cache.generation == 4294967295 { abort("inactive resolution cache"); }
    if cache.entries.len == 0 {
        let error = grow(cache); if error != Error.none { return error; }
    }
    var slot = index(root, cache.entries.len - 1);
    while cache.entries[slot].generation == cache.generation {
        if cache.entries[slot].root == root { cache.entries[slot].result = result; return Error.none; }
        slot = (slot + 1) & (cache.entries.len - 1);
    }
    if cache.count >= cache.entries.len - cache.entries.len / 4 {
        let error = grow(cache); if error != Error.none { return error; }
        slot = index(root, cache.entries.len - 1);
        while cache.entries[slot].generation == cache.generation { slot = (slot + 1) & (cache.entries.len - 1); }
    }
    cache.entries[slot] = Entry { cache.generation, root, result };
    cache.count++; cache.high_water = max(cache.high_water, root as i64 + 1);
    return Error.none;
}
