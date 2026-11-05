// Fixed map descriptors keep recursive owners free of resizable locals.
namespace blot_support_pooled_map;
import dictionary;
struct Map<K,V> { count: i64 = 0, slots: dictionary_slot<K,V>[:] = [] }
fn probe<K,V>(map: const Map<K,V>&,key: K) -> i64 {
    if map.count == 0 { return -1; } let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get<K,V>(map: const Map<K,V>&,key: K) -> V? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains<K,V>(map: const Map<K,V>&,key: K) -> bool { return probe(map,key) >= 0; }
fn release<K,V>(slots: dictionary_slot<K,V>[:],pool: dictionary_slot<K,V>[>..]&) { if slots.len != 0 { pool.free_slice(slots); } }
fn grow<K,V>(map: Map<K,V>&,capacity: i64,pool: dictionary_slot<K,V>[>..]&) {
    let replacement = pool.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<K,V> { default<K>(),default<V>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots,pool); map.slots = replacement;
}
fn insert<K,V>(map: Map<K,V>&,key: K,value: V,pool: dictionary_slot<K,V>[>..]&) -> bool {
    if map.slots.len == 0 { grow(map,8,pool); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2,pool); }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<K,V> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<K,V> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove<K,V>(map: Map<K,V>&,key: K) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<K,V> { default<K>(),default<V>(),0 }; map.count--; return true;
}
fn clear<K,V>(map: Map<K,V>&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit<K,V>(map: Map<K,V>&,pool: dictionary_slot<K,V>[>..]&) { release(map.slots,pool); map.slots = []; map.count = 0; }
fn clone<K,V>(map: const Map<K,V>&,pool: dictionary_slot<K,V>[>..]&) -> Map<K,V> { var copy = Map<K,V> {}; if map.slots.len != 0 { let slots = pool.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<K,V,F>(map: Map<K,V>&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }
