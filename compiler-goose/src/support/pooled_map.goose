// Fixed map descriptors keep recursive owners free of resizable locals.
namespace blot_support_pooled_map;
import .word_hash;
import dictionary;
struct Map<K,V> { count: i64 = 0, slots: dictionary_slot<K,V>[:] = default<dictionary_slot<K,V>[:]>() }
fn probe<M,K>(map: const M&,key: K) -> i64 {
    if map.count == 0 { return -1; } let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn getSlots<K,V>(slots: dictionary_slot<K,V>[:],key: K) -> V? {
    if slots.len == 0 { return null; } let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = slots[index].tag; if present == tag && slots[index].key == key { return slots[index].val; } if present == 0 { return null; } index = (index + 1) & mask; }
}
fn get<M,K>(map: const M&,key: K) { return getSlots(map.slots,key); }
fn contains<M,K>(map: const M&,key: K) -> bool { return probe(map,key) >= 0; }
fn release<K,V>(slots: dictionary_slot<K,V>[:],pool: dictionary_slot<K,V>[>..]&) { if slots.len != 0 { pool.free_slice(slots); } }
fn grow<M,K,V>(map: M&,capacity: i64,pool: dictionary_slot<K,V>[>..]&) {
    let old = map.slots.len; let slots = pool.realloc_slice(map.slots,capacity); map.slots = slots;
    if map.count == 0 { return; } let mask = capacity - 1; var empty:i64 = 0;
    while slots[empty].tag != 0 { empty++; }
    for step in 1..old {
        var source = empty + step; if source >= old { source -= old; } let tag = slots[source].tag;
        if tag == 0 { continue; } var destination = (tag as i64) & mask;
        if mask >= 2147483648 { destination = (slots[source].key.hash() & (mask as u64)) as i64; }
        let slot = slots[source]; slots[source].tag = 0;
        while slots[destination].tag != 0 { destination = (destination + 1) & mask; }
        slots[destination] = slot;
    }
}
fn insert<M,K,V>(map: M&,key: K,value: V,pool: dictionary_slot<K,V>[>..]&) -> bool {
    if map.slots.len == 0 { grow(map,8,pool); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2,pool); }
    let slots = pool.realloc_slice(map.slots,map.slots.len);
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = slots[index].tag; if present == 0 { slots[index] = dictionary_slot<K,V> { key,value,tag }; map.count++; return true; } if present == tag && slots[index].key == key { slots[index] = dictionary_slot<K,V> { slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove<M,K>(map: M&,key: K) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    eraseSlot(map.slots[hole]); map.count--; return true;
}
fn eraseSlot<K,V>(slot:dictionary_slot<K,V>&) {slot=default<dictionary_slot<K,V>>();}
fn clear<M>(map: M&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit<M,K,V>(map: M&,pool: dictionary_slot<K,V>[>..]&) { release(map.slots,pool); map.slots = default<dictionary_slot<K,V>[:]>(); map.count = 0; }
fn clone<M,K,V>(map: const M&,pool: dictionary_slot<K,V>[>..]&) -> M { var copy = copy(map); if map.slots.len != 0 { let source = pool.realloc_slice(map.slots,map.slots.len); let slots = pool.alloc_slice(source.len); for slot,index in source { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<M,F>(map: M&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }
