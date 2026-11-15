// The table layout of Zig's std.AutoHashMapUnmanaged(u32, V): hash,
// capacity, growth, probing and clone as std/hash_map.zig (0.17.0). The Zig
// compiler walks some of its maps in slot order and its output depends on
// that order (the checker's imported names and globals, the direct backend's
// binding map), so the port keeps the same layout. Removal is not needed.
// Values are u32 handles.
namespace blot_support_zigmap;
import std;
import support.wyhash;

// A table of `capacity` slots at `base` in the pool: three words per slot,
// [used, key, value].
struct Map { base: u32 = 0, capacity: u32 = 0, size: u32 = 0, available: u32 = 0 }

// AutoContext hashes a u32 key as Wyhash.hash(0, its four bytes).
fn hashKey(key: u32) -> u64 {
    let bytes: u8[4] = [key as! u8, (key >> 8) as! u8, (key >> 16) as! u8, (key >> 24) as! u8];
    return blot_support_wyhash::hash(0, bytes[..]);
}
fn used(pool: const u32[>..]&, map: Map, slot: u32) -> bool { return pool[map.base + slot * 3] != 0; }
fn keyAt(pool: const u32[>..]&, map: Map, slot: u32) -> u32 { return pool[map.base + slot * 3 + 1]; }
fn valueAt(pool: const u32[>..]&, map: Map, slot: u32) -> u32 { return pool[map.base + slot * 3 + 2]; }
// The slot holding `key`, or -1.
fn find(pool: const u32[>..]&, map: Map, key: u32) -> i64 {
    if map.size == 0 { return -1; }
    let mask = map.capacity - 1;
    var slot = (hashKey(key) as! u32) & mask;
    var limit = map.capacity;
    while limit != 0 && used(pool, map, slot) {
        if keyAt(pool, map, slot) == key { return slot; }
        limit -= 1;
        slot = (slot + 1) & mask;
    }
    return -1;
}
fn get(pool: const u32[>..]&, map: Map, key: u32) -> u32, bool {
    let slot = find(pool, map, key);
    if slot < 0 { return 0, false; }
    return valueAt(pool, map, slot as u32), true;
}
fn capacityForSize(size: u32) -> u32 {
    let wanted: u64 = size;
    let least = (wanted * 100) / 80 + 1;
    var capacity: u64 = 1;
    while capacity < least { capacity = capacity * 2; }
    return capacity as! u32;
}
fn allocate(pool: u32[>..]&, capacity: u32) -> Map {
    let base = pool.len as u32;
    for at in 0..(capacity as i64) * 3 { pool.push(0); }
    return Map { base, capacity, 0, ((capacity as u64 * 80) / 100) as! u32 };
}
// putAssumeCapacityNoClobber: the first slot from the key's home that is not used.
fn insertNew(pool: u32[>..]&, map: Map&, key: u32, value: u32) {
    let mask = map.capacity - 1;
    var slot = (hashKey(key) as! u32) & mask;
    while used(pool, map, slot) { slot = (slot + 1) & mask; }
    pool[map.base + slot * 3] = 1;
    pool[map.base + slot * 3 + 1] = key;
    pool[map.base + slot * 3 + 2] = value;
    map.available -= 1;
    map.size += 1;
}
fn copyInto(pool: u32[>..]&, from: Map, to: Map&) {
    for slot in 0..(from.capacity as i64) {
        if !used(pool, from, slot as u32) { continue; }
        insertNew(pool, to, keyAt(pool, from, slot as u32), valueAt(pool, from, slot as u32));
        if to.size == from.size { break; }
    }
}
// Sets key to value. Like Zig's put, room for one more entry is made before
// the key is looked up, so a put of a present key can grow the table.
fn put(pool: u32[>..]&, map: Map&, key: u32, value: u32) {
    if map.available < 1 {
        let load = ((map.capacity as u64 * 80) / 100) as! u32 - map.available;
        var grown = allocate(pool, max(capacityForSize(load + 1), 8));
        if map.size != 0 { copyInto(pool, map, grown); }
        map = grown;
    }
    let slot = find(pool, map, key);
    if slot >= 0 { pool[map.base + (slot as u32) * 3 + 2] = value; return; }
    insertNew(pool, map, key, value);
}
// Zig's clone: a table sized for the entries, filled in slot order.
fn clone(pool: u32[>..]&, map: Map) -> Map {
    if map.size == 0 { return Map {}; }
    var other = allocate(pool, capacityForSize(map.size));
    copyInto(pool, map, other);
    return other;
}
