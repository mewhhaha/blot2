namespace blot_reuse_substitution_keys;
import std;
import dictionary;
import support.error;
import support.wyhash;

type Id = u32;
type Error = blot_error::Error;
struct Entry { variable: u32, value: u32 }
struct Span { start: u32, len: u32 }
// Interned runs chain through a fixed bucket table; lookup compares the stored
// entries, and interning never shrinks storage that live views may alias.
let key_buckets: i64 = 1024;
struct KeyIndex { heads: Id[1024] = [0;1024] }
fn keyBucket(fingerprint: u64) -> i64 { return (fingerprint % (key_buckets as u64)) as i64; }
fn clear(index: KeyIndex&) { for bucket in 0..key_buckets { index.heads[bucket] = 0; } }
struct Store {
    entries: Entry[>..<]&, spans: Span[>..<]&, next: Id[>..<]&,
    buckets: KeyIndex&,
}
fn init(entries: Entry[>..<]&, spans: Span[>..<]&, next: Id[>..<]&, buckets: KeyIndex&) -> Store {
    Store { entries, spans, next, buckets }
}
fn deinit(store: Store&) { store.entries.clear(); store.spans.clear(); store.next.clear(); store.buckets.clear(); }
fn get(store: Store&, id: Id) -> const Entry[:] {
    if id == 0 { return store.entries[..0]; }
    let span = store.spans[id - 1]; return store.entries[span.start..span.start + span.len];
}
fn intern(store: Store&, values: const Entry[:]) -> Id, Error {
    if values.len == 0 { return 0, blot_error::Error.none; }
    var owned: Entry[>..<] = []; owned.append(values);
    var index: i64 = 1;
    while index < owned.len {
        let value = owned[index]; var at = index;
        while at > 0 && value.variable < owned[at - 1].variable { owned[at] = owned[at - 1]; at--; }
        owned[at] = value; index++;
    }
    for at in 1..owned.len {
        if owned[at].variable == owned[at - 1].variable { return 0, blot_error::Error.conflicting_substitution; }
    }
    var hash = blot_support_wyhash::init(0);
    for entry in owned { hash.value(entry.variable); hash.value(entry.value); }
    return internHashed(store, owned, hash.final());
}
fn internHashed(store: Store&, values: const Entry[:], fingerprint: u64) -> Id, Error {
    let bucket = keyBucket(fingerprint); let head = store.buckets.heads[bucket];
    var candidate = head;
    while candidate != 0 {
        if get(store, candidate) == values { return candidate, blot_error::Error.none; }
        candidate = store.next[candidate - 1];
    }
    if store.spans.len >= 4294967294 || values.len > 4294967295 ||
        store.entries.len > 4294967295 - values.len { return 0, blot_error::Error.key_limit; }
    let id = (store.spans.len + 1) as Id;
    store.spans.push(Span { store.entries.len as u32, values.len as u32 , ..});
    store.entries.append(values); store.next.push(head); store.buckets.heads[bucket] = id;
    return id, blot_error::Error.none;
}
