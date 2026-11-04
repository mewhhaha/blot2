namespace blot_reuse_composite_resolution_cache;
import support.error;
import support.option;

type Error = blot_error::Error;
struct Dependency { variable: u32, last: u32, effect: bool = false }
struct Record {
    result: u32 = 0, dependencies: Dependency[8], count: u8 = 0,
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
struct Entry { root: u32 = 0, at: u32 = 0, record: Record }
struct Cache { entries: Entry[>..<]&, physical: u16 = 0, effects_physical: u64 = 0 }
fn init(entries: Entry[>..<]&) -> Cache { Cache { entries } }
fn deinit(cache: Cache&) { cache.entries.clear(); }
fn activate(cache: Cache&, physical: u16, effects_physical: u64) -> bool {
    if physical == 65535 || effects_physical == 18446744073709551615 { return false; }
    if cache.physical != physical || cache.effects_physical != effects_physical {
        for &entry in cache.entries { entry.root = 0; }
        cache.physical = physical; cache.effects_physical = effects_physical;
    }
    return true;
}
fn slot(root: u32, at: u32) -> i64 { ((root * 2654435769 ^ at * 2246822507) >> 28) as i64 }
fn get(cache: Cache&, root: u32, at: u32) -> blot_support::Option<Record> {
    if cache.entries.len == 0 { return blot_support::none<Record>(); }
    let entry = cache.entries[slot(root, at)];
    if entry.root == root && entry.at == at { return blot_support::some(entry.record); }
    return blot_support::none<Record>();
}
fn occupied(cache: Cache&, root: u32, at: u32) -> bool {
    cache.entries.len != 0 && cache.entries[slot(root, at)].root != 0
}
fn put(cache: Cache&, root: u32, at: u32, record: Record) -> Error {
    if cache.entries.len == 0 { cache.entries.resize(16, Entry {}); }
    cache.entries[slot(root, at)] = Entry { root, at, record };
    return Error.none;
}
