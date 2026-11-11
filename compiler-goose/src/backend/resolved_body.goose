// Actual-variant payloads stay typed in one compilation attempt's native pool.
namespace blot_backend_resolved_body;
import dictionary;
import .layout;
import .backend_emission;
type Plan = blot_backend_backend_emission::Plan;
import check.numeric_proof_core;
import support.error;
import support.native;
import support.option;
// Plan lookup chains slots through a fixed bucket table; released slots keep
// their place with body 0, so no index storage shrinks during preparation.
let node_buckets: i64 = 4096;
fn nodeBucket(body: u32,node: u32) -> i64 { return (::hash_combine(::hash(body),::hash(node)) % (node_buckets as u64)) as i64; }
struct Slot { node: u32,payload: Plan..&,next: u32 = 0,body: u32 = 0,chain: u32 = 0 }
struct Header {
    owner_id:u64=0,
    active: bool = true,numeric: blot_support::Option<blot_check_numeric_proof_core::Plan>,has_associated: bool = false,has_numeric_checks: bool = false,
    unit: u32,root: u32,mappings: const blot_backend_layout::Mapping[:],rows: const blot_backend_layout::RowMapping[:],rows_evidence: u32 = 0,has_owners: bool = false,first: u32 = 0,last: u32 = 0,
}
// Sinks chain through a fixed bucket table over grow-only scalar records.
struct Sink { body: u32,binding: u32,node: u32,chain: u32 = 0 }
fn sinkBucket(body: u32,binding: u32) -> i64 { return (::hash_combine(::hash(body),::hash(binding)) % 1024) as i64; }
var headers: Header[>..<] = [];
var slots: Slot[>..<] = [];
var node_heads: u32[4096] = [0;4096];
var sink_records: Sink[>..] = [];
var sink_count: i64 = 0; // Records past the count are stale and reused; the run never shrinks.
var sink_heads: u32[1024] = [0;1024];
var payloads: Plan..[>..] = [];
reusable[] var owned_mappings: blot_backend_layout::Mapping[>..] = [];
reusable[] var owned_rows: blot_backend_layout::RowMapping[>..] = [];
fn create(unit: u32,root: u32,mappings: const blot_backend_layout::Mapping[:],rows: const blot_backend_layout::RowMapping[:]) -> u32,blot_error::Error {
    if headers.len >= 4294967295 { return 0,blot_error::Error.module_too_large; }
    var copied_mappings: const blot_backend_layout::Mapping[:] = default<const blot_backend_layout::Mapping[:]>(); if mappings.len != 0 { let out = owned_mappings.alloc_slice(mappings.len); for value,index in mappings { out[index] = value; } copied_mappings = out; }
    var copied_rows: const blot_backend_layout::RowMapping[:] = default<const blot_backend_layout::RowMapping[:]>(); if rows.len != 0 { let out = owned_rows.alloc_slice(rows.len); for value,index in rows { out[index] = value; } copied_rows = out; }
    headers.push(Header { owner_id:blot_native::fresh_owner_id(),unit: unit,root: root,mappings: copied_mappings,rows: copied_rows , ..}); return headers.len as u32,blot_error::Error.none;
}
fn header(id: u32) -> Header { assert(id != 0 && id <= headers.len && headers[id - 1].active); return headers[id - 1]; }
fn entryCount(body: u32) -> i64 { var count: i64 = 0; var cursor = headers[body - 1].first; while cursor != 0 { count++; cursor = slots[cursor - 1].next; } return count; }
fn sinkCount(body: u32) -> i64 { var count: i64 = 0; for record in sink_records[..sink_count] { if record.body == body { count++; } } return count; }
fn put(body: u32,node: u32,entry: Plan) -> blot_error::Error {
    assert(body != 0 && body <= headers.len && headers[body - 1].active); assert(findSlot(body,node) == 0);
    if slots.len >= 4294967295 { return blot_error::Error.module_too_large; }
    let payload .= payloads.push(entry); let next = (slots.len + 1) as u32; let bucket = nodeBucket(body,node); slots.push(Slot { node: node,payload: payload,body: body,chain: node_heads[bucket] , ..}); node_heads[bucket] = next;
    let previous = headers[body - 1].last; if previous != 0 { slots[previous - 1].next = next; } else { headers[body - 1].first = next; }
    headers[body - 1].last = next; return blot_error::Error.none;
}
fn findSlot(body: u32,node: u32) -> u32 { assert(body != 0); var id = node_heads[nodeBucket(body,node)]; while id != 0 { let slot = slots[id - 1]; if slot.body == body && slot.node == node { return id; } id = slot.chain; } return 0; }
fn getRef(body: u32,node: u32) -> Plan..& { let id = findSlot(body,node); assert(id != 0); return slots[id - 1].payload; }
fn get(body: u32,node: u32) -> Plan { getRef(body,node) }
fn contains(body: u32,node: u32) -> bool { findSlot(body,node) != 0 }
fn findSink(body: u32,binding: u32) -> u32 { var id = sink_heads[sinkBucket(body,binding)]; while id != 0 { let record = sink_records[id - 1]; if record.body == body && record.binding == binding { return id; } id = record.chain; } return 0; }
fn sink(body: u32,binding: u32) -> blot_support::Option<u32> { let id = findSink(body,binding); if id != 0 { return blot_support::some(sink_records[id - 1].node); } return blot_support::none<u32>(); }
fn setSink(body: u32,binding: u32,node: u32) { let id = findSink(body,binding); if id != 0 { sink_records[id - 1].node = node; return; } let bucket = sinkBucket(body,binding); let record = Sink { body: body,binding: binding,node: node,chain: sink_heads[bucket] }; if sink_count < sink_records.len { sink_records[sink_count] = record; } else { sink_records.push(record); } sink_count++; sink_heads[bucket] = sink_count as u32; }
recursive fn release(body: u32) {
    assert(body != 0 && body <= headers.len); if !headers[body - 1].active { return; } let snapshot = headers[body - 1]; headers[body - 1].active = false;
    if snapshot.numeric.present { snapshot.numeric.value.deinit(); } var cursor = snapshot.first;
    while cursor != 0 {
        let slot = slots[cursor - 1]; var entry: Plan = slot.payload; entry.deinit(); slots[cursor - 1].body = 0; cursor = slot.next;
    }
    if snapshot.mappings.len != 0 { owned_mappings.free_slice(snapshot.mappings); }
    if snapshot.rows.len != 0 { owned_rows.free_slice(snapshot.rows); }
    // Payload bytes are released together after every attempt. No reference to
    // them enters retained artifacts, whose descriptors contain numeric IDs.
}
fn resetIndex() { for bucket in 0..node_buckets { node_heads[bucket] = 0; } }
// Run teardown releases the plan headers and index but keeps the grow-only payload
// pool: a returned Result outlives the run, and the next attempt's reset empties it.
fn deinit() {
    for index in 0..headers.len { if headers[index].active { release((index + 1) as u32); } }
    for bucket in 0..1024 { sink_heads[bucket] = 0; } sink_count = 0; headers.clear(); resetIndex(); slots=[];
}
fn reset() { deinit(); slots=[]; payloads=[]; }

fn validBodyRead(body:u32,owner_id:u64)->bool {return body!=0 && body<=headers.len && headers[body-1].active && owner_id!=0 && headers[body-1].owner_id==owner_id;}
fn readMappings(body:u32,owner_id:u64,offset:i64,length:i64)->const blot_backend_layout::Mapping[:] {assert(validBodyRead(body,owner_id));let source=headers[body-1].mappings;assert(offset>=0 && length>=0 && offset<=source.len && length<=source.len-offset);if length==0 {return default<const blot_backend_layout::Mapping[:]>();}let owned=owned_mappings.realloc_slice(source,source.len);assert(blot_support::same_slice_identity(owned,source));let start=owned_mappings.index_of(owned[0]);assert(start>=0 && source.len<=owned_mappings.len-start);return owned_mappings[start+offset..start+offset+length];}
fn readRows(body:u32,owner_id:u64,offset:i64,length:i64)->const blot_backend_layout::RowMapping[:] {assert(validBodyRead(body,owner_id));let source=headers[body-1].rows;assert(offset>=0 && length>=0 && offset<=source.len && length<=source.len-offset);if length==0 {return default<const blot_backend_layout::RowMapping[:]>();}let owned=owned_rows.realloc_slice(source,source.len);assert(blot_support::same_slice_identity(owned,source));let start=owned_rows.index_of(owned[0]);assert(start>=0 && source.len<=owned_rows.len-start);return owned_rows[start+offset..start+offset+length];}
