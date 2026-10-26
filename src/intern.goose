// Exact structural keys are compiler scratch. Bucket probes never inspect Core rows.
import std;
struct KeySlot<K> { key: K, value: u32, next: u32 }
struct KeyIndex<K> { heads: u32[1024] = [0; 1024], slots: KeySlot<K>[>..] = [] }
fn key_index_get<K>(index: KeyIndex<K>&, key: K) -> u32 { var at = index.heads[(hash(key) & 1023) as u32]; while at != 0 { let slot = index.slots[at - 1]; if slot.key == key { return slot.value; } at = slot.next; } return 0; }
fn key_index_insert<K>(index: KeyIndex<K>&, key: K, value: u32) { let bucket = (hash(key) & 1023) as u32; var at = index.heads[bucket]; while at != 0 { if index.slots[at - 1].key == key { index.slots[at - 1].value = value; return; } at = index.slots[at - 1].next; } index.slots.push(KeySlot<K> { key: key, value: value, next: index.heads[bucket] }); index.heads[bucket] = index.slots.len as u32; }
