// A hash map from u64 to u32 over one grow-only array: it never shrinks, so
// views held across an insert stay valid for the lifetime checker (Goose
// spec 5.2 counts a dictionary insert as a shrink of its slots).
namespace blot_direct_map;
import std;

// words: bucket regions and nodes. A bucket holds the offset of its first
// node, or 0. A node is four words: key low, key high, value, next node.
// Growth appends a larger bucket region and relinks every node into it.
struct U64Map { count: u32 = 0, base: u32 = 0, mask: u32 = 0, words: u32[>..] = [] }

fn bucketOf(map: const U64Map&, key: u64) -> u32 { return map.base + ((::hash(key) as! u32) & map.mask); }
fn find(map: const U64Map&, key: u64) -> u32 {
    if map.count == 0 { return 0; }
    var at = map.words[bucketOf(map, key)];
    let low = key as! u32;
    let high = (key >> 32) as! u32;
    while at != 0 {
        if map.words[at] == low && map.words[at + 1] == high { return at; }
        at = map.words[at + 3];
    }
    return 0;
}
fn get(map: const U64Map&, key: u64) -> u32, bool {
    let at = find(map, key);
    if at == 0 { return 0, false; }
    return map.words[at + 2], true;
}
fn clear(map: U64Map&) {
    if map.count == 0 { return; }
    for at in 0..((map.mask as i64) + 1) { map.words[(map.base as i64) + at] = 0; }
    map.count = 0;
}
fn contains(map: const U64Map&, key: u64) -> bool { return find(map, key) != 0; }
fn grow(map: U64Map&, buckets: u32) {
    let old_base = map.base;
    let old_count = map.mask + 1;
    let had = map.words.len != 0;
    let new_base = map.words.len as u32;
    for at in 0..(buckets as i64) { map.words.push(0); }
    map.base = new_base;
    map.mask = buckets - 1;
    if !had { return; }
    for bucket in 0..(old_count as i64) {
        var at = map.words[old_base + bucket];
        while at != 0 {
            let next = map.words[at + 3];
            let high: u64 = map.words[at + 1];
            let key = map.words[at] | (high << 32);
            let home = bucketOf(map, key);
            map.words[at + 3] = map.words[home];
            map.words[home] = at;
            at = next;
        }
    }
}
// Sets key to value; true when the key was new.
fn put(map: U64Map&, key: u64, value: u32) -> bool {
    let found = find(map, key);
    if found != 0 { map.words[found + 2] = value; return false; }
    if map.words.len == 0 { grow(map, 16); }
    else if map.count >= map.mask + 1 { grow(map, (map.mask + 1) * 2); }
    let home = bucketOf(map, key);
    let at = map.words.len as u32;
    map.words.push(key as! u32);
    map.words.push((key >> 32) as! u32);
    map.words.push(value);
    map.words.push(map.words[home]);
    map.words[home] = at;
    map.count += 1;
    return true;
}
