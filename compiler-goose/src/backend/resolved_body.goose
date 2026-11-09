// Actual-variant payloads stay typed in one compilation attempt's native pool.
namespace blot_backend_resolved_body;
import dictionary;
import .layout;
import .backend_emission;
type Plan = blot_backend_backend_emission::Plan;
import check.numeric_proof_core;
import support.error;
import support.option;
struct NodeKey { body: u32,node: u32 }
fn hash(key: NodeKey) -> u64 { ::hash_combine(::hash(key.body),::hash(key.node)) }
struct Slot { node: u32,payload: Plan..&,next: u32 = 0 }
struct Header {
    active: bool = true,numeric: blot_support::Option<blot_check_numeric_proof_core::Plan>,has_associated: bool = false,has_numeric_checks: bool = false,
    unit: u32,root: u32,mappings: const blot_backend_layout::Mapping[:],rows: const blot_backend_layout::RowMapping[:],rows_evidence: u32 = 0,has_owners: bool = false,first: u32 = 0,last: u32 = 0,
}
struct SinkKey { body: u32,binding: u32 }
fn hash(key: SinkKey) -> u64 { ::hash_combine(::hash(key.body),::hash(key.binding)) }
var headers: Header[>..<] = [];
var slots: Slot[>..<] = [];
var entries: dictionary<NodeKey,Plan..&?> = dictionary<NodeKey,Plan..&?>{..};
var sinks: dictionary<SinkKey,u32> = dictionary<SinkKey,u32>{..};
var payloads: Plan..[>..] = [];
reusable[] var owned_mappings: blot_backend_layout::Mapping[>..] = [];
reusable[] var owned_rows: blot_backend_layout::RowMapping[>..] = [];
fn create(unit: u32,root: u32,mappings: const blot_backend_layout::Mapping[:],rows: const blot_backend_layout::RowMapping[:]) -> u32,blot_error::Error {
    if headers.len >= 4294967295 { return 0,blot_error::Error.module_too_large; }
    var copied_mappings: const blot_backend_layout::Mapping[:] = default<const blot_backend_layout::Mapping[:]>(); if mappings.len != 0 { let out = owned_mappings.alloc_slice(mappings.len); for value,index in mappings { out[index] = value; } copied_mappings = out; }
    var copied_rows: const blot_backend_layout::RowMapping[:] = default<const blot_backend_layout::RowMapping[:]>(); if rows.len != 0 { let out = owned_rows.alloc_slice(rows.len); for value,index in rows { out[index] = value; } copied_rows = out; }
    headers.push(Header { unit: unit,root: root,mappings: copied_mappings,rows: copied_rows , ..}); return headers.len as u32,blot_error::Error.none;
}
fn header(id: u32) -> Header { assert(id != 0 && id <= headers.len && headers[id - 1].active); return headers[id - 1]; }
fn entryCount(body: u32) -> i64 { var count: i64 = 0; var cursor = headers[body - 1].first; while cursor != 0 { count++; cursor = slots[cursor - 1].next; } return count; }
fn sinkCount(body: u32) -> i64 { var count: i64 = 0; sinks.each() { key,value=>{ if key.body == body { count++; } } } return count; }
fn put(body: u32,node: u32,entry: Plan) -> blot_error::Error {
    assert(body != 0 && body <= headers.len && headers[body - 1].active); let key = NodeKey { body,node , ..}; assert(!::contains(entries,key));
    if slots.len >= 4294967295 { return blot_error::Error.module_too_large; }
    let payload .= payloads.push(entry); let next = (slots.len + 1) as u32; slots.push(Slot { node,payload , ..});
    let previous = headers[body - 1].last; if previous != 0 { slots[previous - 1].next = next; } else { headers[body - 1].first = next; }
    headers[body - 1].last = next; ::insert(entries,key,payload); return blot_error::Error.none;
}
fn getRef(body: u32,node: u32) -> Plan..& { let found = ::get(entries,NodeKey { body,node , ..}); assert(found); return found; }
fn get(body: u32,node: u32) -> Plan { getRef(body,node) }
fn contains(body: u32,node: u32) -> bool { ::contains(entries,NodeKey { body,node , ..}) }
fn sink(body: u32,binding: u32) -> blot_support::Option<u32> { let value = ::get(sinks,SinkKey { body,binding , ..}); if value { return blot_support::some(value); } return blot_support::none<u32>(); }
fn setSink(body: u32,binding: u32,node: u32) { ::insert(sinks,SinkKey { body,binding , ..},node); }
recursive fn release(body: u32) {
    assert(body != 0 && body <= headers.len); if !headers[body - 1].active { return; } let snapshot = headers[body - 1]; headers[body - 1].active = false;
    if snapshot.numeric.present { snapshot.numeric.value.deinit(); } var cursor = snapshot.first;
    while cursor != 0 {
        let slot = slots[cursor - 1]; var entry: Plan = slot.payload; entry.deinit(); ::remove(entries,NodeKey { body,slot.node , ..}); cursor = slot.next;
    }
    if snapshot.mappings.len != 0 { owned_mappings.free_slice(snapshot.mappings); }
    if snapshot.rows.len != 0 { owned_rows.free_slice(snapshot.rows); }
    // Payload bytes are released together after every attempt. No reference to
    // them enters retained artifacts, whose descriptors contain numeric IDs.
}
fn deinit() {
    for index in 0..headers.len { if headers[index].active { release((index + 1) as u32); } }
    sinks.clear(); headers.clear(); entries=dictionary<NodeKey,Plan..&?>{..}; slots=[]; payloads=[];
}
