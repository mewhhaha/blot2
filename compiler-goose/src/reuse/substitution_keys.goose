namespace blot_reuse_substitution_keys;
import std;
import dictionary;
import support.error;
import support.wyhash;

type Id = u32;
type Error = blot_error::Error;
struct Entry { variable: u32, value: u32 }
struct Span { start: u32, len: u32 }
struct Store {
    entries: Entry[>..<]&, spans: Span[>..<]&, next: Id[>..<]&,
    buckets: dictionary<u64, Id>&,
}
fn init(entries: Entry[>..<]&, spans: Span[>..<]&, next: Id[>..<]&, buckets: dictionary<u64, Id>&) -> Store {
    Store { entries, spans, next, buckets }
}
fn deinit(store: Store&) { store.entries.clear(); store.spans.clear(); store.next.clear(); store.buckets.clear(); }
fn get(store: Store&, id: Id) -> const Entry[:] {
    if id == 0 { return store.entries[..0]; }
    let span = store.spans[id - 1]; return store.entries[span.start..span.start + span.len];
}
fn intern(store: Store&, values: const Entry[:]) -> Id, Error {
    if values.len == 0 { return 0, Error.none; }
    var owned: Entry[>..<] = []; owned.append(values);
    var index: i64 = 1;
    while index < owned.len {
        let value = owned[index]; var at = index;
        while at > 0 && value.variable < owned[at - 1].variable { owned[at] = owned[at - 1]; at--; }
        owned[at] = value; index++;
    }
    for at in 1..owned.len {
        if owned[at].variable == owned[at - 1].variable { return 0, Error.conflicting_substitution; }
    }
    var hash = blot_support_wyhash::init(0);
    for entry in owned { hash.value(entry.variable); hash.value(entry.value); }
    return internHashed(store, owned, hash.final());
}
fn internHashed(store: Store&, values: const Entry[:], fingerprint: u64) -> Id, Error {
    var head: Id = 0; { let optional_source_3 .= store.buckets.get(fingerprint); if optional_source_3 { let found = optional_source_3; head = found;  } }
    var candidate = head;
    while candidate != 0 {
        if get(store, candidate) == values { return candidate, Error.none; }
        candidate = store.next[candidate - 1];
    }
    if store.spans.len >= 4294967294 || values.len > 4294967295 ||
        store.entries.len > 4294967295 - values.len { return 0, Error.key_limit; }
    let id = (store.spans.len + 1) as Id;
    store.spans.push(Span { store.entries.len as u32, values.len as u32 });
    store.entries.append(values); store.next.push(head); store.buckets.insert(fingerprint, id);
    return id, Error.none;
}
