// Actual-variant payloads stay typed in one compilation attempt's native pool.
namespace blot_backend_resolved_body;
import dictionary;
import .layout;
import check.numeric_proof_core;
import support.error;
import support.option;
struct NodeKey { body: u32,node: u32 }
fn hash(key: NodeKey) -> u64 { ::hash_combine(::hash(key.body),::hash(key.node)) }
struct Slot<E> { node: u32,payload: E..&,next: u32 = 0 }
struct Header {
    active: bool = true,numeric: blot_support::Option<blot_check_numeric_proof_core::Plan>,has_associated: bool = false,has_numeric_checks: bool = false,
    unit: u32,root: u32,mappings: const blot_backend_layout::Mapping[:],rows: const blot_backend_layout::RowMapping[:],rows_evidence: u32 = 0,has_owners: bool = false,first: u32 = 0,last: u32 = 0,
}
struct SinkKey { body: u32,binding: u32 }
fn hash(key: SinkKey) -> u64 { ::hash_combine(::hash(key.body),::hash(key.binding)) }
struct Tables<E> { headers: Header[>..<]&,slots: Slot<E>[>..<]&,entries: dictionary<NodeKey,E..&?>&,sinks: dictionary<SinkKey,u32>&,payloads: E..[>..]& }
struct Store<E> { headers: Header[>..<]&,slots: Slot<E>[>..<]&,entries: dictionary<NodeKey,E..&?>&,sinks: dictionary<SinkKey,u32>&,payloads: E..[>..]& }
reusable[] var owned_mappings: blot_backend_layout::Mapping[>..] = [];
reusable[] var owned_rows: blot_backend_layout::RowMapping[>..] = [];
fn init<E>(tables: Tables<E>) -> Store<E> { Store<E> { tables.headers,tables.slots,tables.entries,tables.sinks,tables.payloads } }
fn create<E>(store: Store<E>&,unit: u32,root: u32,mappings: const blot_backend_layout::Mapping[:],rows: const blot_backend_layout::RowMapping[:]) -> u32,blot_error::Error {
    if store.headers.len >= 4294967295 { return 0,blot_error::Error.module_too_large; }
    var copied_mappings: const blot_backend_layout::Mapping[:] = default<const blot_backend_layout::Mapping[:]>(); if mappings.len != 0 { let out = owned_mappings.alloc_slice(mappings.len); for value,index in mappings { out[index] = value; } copied_mappings = out; }
    var copied_rows: const blot_backend_layout::RowMapping[:] = default<const blot_backend_layout::RowMapping[:]>(); if rows.len != 0 { let out = owned_rows.alloc_slice(rows.len); for value,index in rows { out[index] = value; } copied_rows = out; }
    store.headers.push(Header { unit: unit,root: root,mappings: copied_mappings,rows: copied_rows , ..}); return store.headers.len as u32,blot_error::Error.none;
}
fn header<E>(store: Store<E>&,id: u32) -> Header { assert(id != 0 && id <= store.headers.len && store.headers[id - 1].active); return store.headers[id - 1]; }
fn entryCount<E>(store: const Store<E>&,body: u32) -> i64 { var count: i64 = 0; var cursor = store.headers[body - 1].first; while cursor != 0 { count++; cursor = store.slots[cursor - 1].next; } return count; }
fn sinkCount<E>(store: Store<E>&,body: u32) -> i64 { var count: i64 = 0; store.sinks.each() { key,value=>{ if key.body == body { count++; } } } return count; }
fn put<E>(store: Store<E>&,body: u32,node: u32,entry: E) -> blot_error::Error {
    assert(body != 0 && body <= store.headers.len && store.headers[body - 1].active); let key = NodeKey { body,node , ..}; assert(!store.entries.contains(key));
    if store.slots.len >= 4294967295 { return blot_error::Error.module_too_large; }
    let payload .= store.payloads.push(entry); let next = (store.slots.len + 1) as u32; store.slots.push(Slot<E> { node,payload , ..});
    let previous = store.headers[body - 1].last; if previous != 0 { store.slots[previous - 1].next = next; } else { store.headers[body - 1].first = next; }
    store.headers[body - 1].last = next; store.entries.insert(key,payload); return blot_error::Error.none;
}
fn getRef<E>(store: Store<E>&,body: u32,node: u32) -> E..& { let found = store.entries.get(NodeKey { body,node , ..}); assert(found); return found; }
fn get<E>(store: Store<E>&,body: u32,node: u32) -> E { getRef(store,body,node) }
fn contains<E>(store: Store<E>&,body: u32,node: u32) -> bool { store.entries.contains(NodeKey { body,node , ..}) }
fn sink<E>(store: Store<E>&,body: u32,binding: u32) -> blot_support::Option<u32> { let value = store.sinks.get(SinkKey { body,binding , ..}); if value { return blot_support::some(value); } return blot_support::none<u32>(); }
fn setSink<E>(store: Store<E>&,body: u32,binding: u32,node: u32) { store.sinks.insert(SinkKey { body,binding , ..},node); }
recursive fn release<E>(store: Store<E>&,body: u32) {
    assert(body != 0 && body <= store.headers.len); if !store.headers[body - 1].active { return; } let snapshot = store.headers[body - 1]; store.headers[body - 1].active = false;
    if snapshot.numeric.present { snapshot.numeric.value.deinit(); } var cursor = snapshot.first;
    while cursor != 0 {
        let slot = store.slots[cursor - 1]; var entry: E = slot.payload; entry.deinit(store); store.entries.remove(NodeKey { body,slot.node , ..}); cursor = slot.next;
    }
    if snapshot.mappings.len != 0 { owned_mappings.free_slice(snapshot.mappings); }
    if snapshot.rows.len != 0 { owned_rows.free_slice(snapshot.rows); }
    // Payload bytes are released together after every attempt. No reference to
    // them enters retained artifacts, whose descriptors contain numeric IDs.
}
fn deinit<E>(store: Store<E>&) {
    for index in 0..store.headers.len { if store.headers[index].active { release(store,(index + 1) as u32); } }
    store.entries.clear(); store.sinks.clear(); store.slots.clear(); store.headers.clear(); store.payloads.clear();
}
