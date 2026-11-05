// Canonical owner ordinals terminate stored-borrow cycles at numbered owners.
namespace blot_backend_storage_owner_graph;
import dictionary;
import .storage_type_key;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;
type Error = blot_error::Error;
struct Owners { storage: i64[:] = default<i64[:]>(),items: i64[:] = default<i64[:]>() }
reusable[] var owner_runs: i64[>..] = [];
reusable[] var ordinal_slots: dictionary_slot<i64,i64>[>..] = [];
struct Graph<V> { owners: Owners,ordinals: blot_support_pooled_map::Map<i64,i64>,remaining: i64 = 100000 }
fn deinit<V>(graph: Graph<V>&) { blot_support_pooled_buffer::deinit(graph.owners,owner_runs); blot_support_pooled_map::deinit(graph.ordinals,ordinal_slots); graph.remaining = 0; }
fn init<V,C,R>(context: const C&,roots: const R[..],arguments: const V[..]) -> Graph<V>,Error {
    var graph = Graph<V> {..};
    recursive fn build() -> Error { for argument in arguments { let error = visit(graph,context,argument,roots.len,false,0); if error != blot_error::Error.none { return error; } } var at: i64 = 0; while at < graph.owners.items.len { let element = roots[graph.owners.items[at]].element; let error = visit(graph,context,element,roots.len,true,0); if error != blot_error::Error.none { return error; } at++; } return blot_error::Error.none; }
    let error = build(); if error != blot_error::Error.none { graph.deinit(); return Graph<V> {..},error; } return graph,blot_error::Error.none;
}
fn result<V,C,R>(context: const C&,roots: const R[..],inputs: i64,output: V,fixed_region: u32) -> Graph<V>,Error {
    var graph = Graph<V> {..}; var donors = Owners {..};
    recursive fn build() -> Error { for index in 0..inputs { let error = add(graph,index,roots.len); if error != blot_error::Error.none { return error; } } let visited = resultValue(graph,context,output,roots.len,inputs,false,donors,0); if visited != blot_error::Error.none { return visited; }
        for index in graph.owners.items[inputs..] { let owner = roots[index]; if !owner.live || owner.persistent || owner.dedicated || owner.stack != fixed_region || !context.plainInlineValue(owner.element) { return blot_error::Error.declined; } if !contains(donors.items,index) { return blot_error::Error.declined; } } return blot_error::Error.none;
    } let error = build(); blot_support_pooled_buffer::deinit(donors,owner_runs); if error != blot_error::Error.none { graph.deinit(); return Graph<V> {..},error; } return graph,blot_error::Error.none;
}
fn contains(values: const i64[:],value: i64) -> bool { for item in values { if item == value { return true; } } return false; }
recursive fn resultValue<V,C>(graph: Graph<V>&,context: const C&,value: V,owner_count: i64,inputs: i64,conditional: bool,donors: Owners&,depth: i64) -> Error {
    if graph.remaining == 0 || depth > 128 { return blot_error::Error.declined; } graph.remaining--; var fresh = value.root.present && value.root.value >= inputs; let others = context.otherRoots(value); for owner in others { if owner >= inputs { fresh = true; } } if fresh && others.len != 0 { return blot_error::Error.declined; }
    if value.root.present { let owner = value.root.value; let added = add(graph,owner,owner_count); if added != blot_error::Error.none { return added; } if owner >= inputs && !conditional { match value.tag { array=>{ match value.mode { fixed=>{},_=>{ return blot_error::Error.declined; }, } if !contains(donors.items,owner) { let appended = blot_support_pooled_buffer::push(donors,owner,owner_runs); if appended != blot_error::Error.none { return appended; } } },_=>{}, } } }
    for owner in others { let error = add(graph,owner,owner_count); if error != blot_error::Error.none { return error; } } for field in context.children(value) { let error = resultValue(graph,context,field,owner_count,inputs,conditional || value.variant_tags.len != 0,donors,depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn add<V>(graph: Graph<V>&,owner: i64,owner_count: i64) -> Error {
    if graph.remaining == 0 || owner >= owner_count { return blot_error::Error.declined; } graph.remaining--; if blot_support_pooled_map::contains(graph.ordinals,owner) { return blot_error::Error.none; } if graph.owners.items.len >= 65536 { return blot_error::Error.declined; }
    let reserved = blot_support_pooled_buffer::ensure(graph.owners,graph.owners.items.len + 1,owner_runs); if reserved != blot_error::Error.none { return reserved; } blot_support_pooled_map::insert(graph.ordinals,owner,graph.owners.items.len,ordinal_slots); let position = graph.owners.items.len; graph.owners.storage[position] = owner; graph.owners.items = graph.owners.storage[..position + 1]; return blot_error::Error.none;
}
recursive fn visit<V,C>(graph: Graph<V>&,context: const C&,value: V,owner_count: i64,stored: bool,depth: i64) -> Error {
    if graph.remaining == 0 || depth > 128 || value.host.present { return blot_error::Error.declined; } graph.remaining--;
    match value.tag { array,callable=>{ if stored { return blot_error::Error.declined; } },_=>{}, }
    if !stored { match value.tag { scalar,aggregate,callable=>{},_=>{ if !value.root.present { return blot_error::Error.declined; } }, } }
    match value.tag { callable=>{ if !value.callable.present { return blot_error::Error.declined; } },_=>{}, }
    if value.root.present { let error = add(graph,value.root.value,owner_count); if error != blot_error::Error.none { return error; } } for owner in context.otherRoots(value) { let error = add(graph,owner,owner_count); if error != blot_error::Error.none { return error; } } for field in context.children(value) { let error = visit(graph,context,field,owner_count,stored,depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn ordinal<V>(graph: const Graph<V>&,owner: i64) -> i64,Error { let found .= blot_support_pooled_map::get(graph.ordinals,owner); if found { return found,blot_error::Error.none; } return 0,blot_error::Error.declined; }
recursive fn edges<V,C,D>(graph: const Graph<V>&,context: const C&,value: V,evidence: D&) -> Error {
    var first: u32 = 4294967295; if value.root.present { let selected,error = ordinal(graph,value.root.value); if error != blot_error::Error.none { return error; } first = selected as u32; } let root = blot_backend_storage_type_key::appendOutput(evidence,first); if root != blot_error::Error.none { return root; } let others = context.otherRoots(value); let count = blot_backend_storage_type_key::appendOutput(evidence,others.len as u32); if count != blot_error::Error.none { return count; }
    for owner in others { let selected,error = ordinal(graph,owner); if error != blot_error::Error.none { return error; } let appended = blot_backend_storage_type_key::appendOutput(evidence,selected as u32); if appended != blot_error::Error.none { return appended; } } let fields = context.children(value); let children = blot_backend_storage_type_key::appendOutput(evidence,fields.len as u32); if children != blot_error::Error.none { return children; } for field in fields { let error = edges(graph,context,field,evidence); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
