// Immutable SSA identities prove unchanged aggregate transport on every edge.
namespace blot_backend_storage_transport;
import dictionary;
import check.core;
import check.types;
import support.error;
import support.option;
import support.pooled_map;
import support.pooled_buffer;
import support.native;
type Error = blot_error::Error;
struct Position { loop_: u32,ordinal: i64 }
struct Exit { node: u32,next: blot_support::Option<i64> }
struct Hypothesis { iteration: u32,anchor: u32 }
struct Query { remaining: i64 = 100000,hypothesis: blot_support::Option<Hypothesis> }
struct Lane { binding: u32,field: const u8[:] }
struct LaneQuery { remaining: i64 = 100000,iteration: u32 = 0,anchor: blot_support::Option<Lane> }
enum State { building,changed,invariant }
struct Exits { storage: Exit[:] = default<Exit[:]>(),items: Exit[:] = default<Exit[:]>() }
reusable[] var exit_runs: Exit[>..] = [];
reusable[] var ordinal_slots: dictionary_slot<u32,i64>[>..] = [];
reusable[] var position_slots: dictionary_slot<u32,Position>[>..] = [];
reusable[] var state_slots: dictionary_slot<u32,State>[>..] = [];
struct Index {
    module: const blot_check_core::Module&,owner_id: u64,lease: i64,
    merges: blot_support_pooled_map::Map<u32,i64>,positions: blot_support_pooled_map::Map<u32,Position>,first_exit: blot_support_pooled_map::Map<u32,i64>,exits: Exits,
    remaining: i64 = 1000000,active: i64 = 0,lane_remaining: i64 = 1000000,states: blot_support_pooled_map::Map<u32,State>,
}
reusable var indexes: Index[>..] = [];
fn create(module: const blot_check_core::Module&) -> Index?,Error {
    if module.nodes.len > 1000000 || module.bindings.len > 100000 || module.merges.len > 100000 { return null,blot_error::Error.none; } let at = indexes.alloc_index(Index { module: module,owner_id: blot_native::fresh_owner_id(),lease: -1 , ..}); let index: Index& = indexes[at]; index.lease = at;
    for merge,ordinal in module.merges { blot_support_pooled_map::insert(index.merges,merge.result,ordinal,ordinal_slots); }
    for node,ordinal in module.nodes { let id = ordinal as u32; if node.tag == blot_check_core::Tag.loop_ { for carry,position in module.loopCarries(id) { blot_support_pooled_map::insert(index.positions,carry.outgoing,Position { loop_: id,ordinal: position , ..},position_slots); } }
        if node.tag == blot_check_core::Tag.break_ { var next = blot_support::none<i64>(); let previous .= blot_support_pooled_map::get(index.first_exit,node.a); if previous { next = blot_support::some<i64>(previous); } let added = blot_support_pooled_buffer::push(index.exits,Exit { node: id,next: next , ..},exit_runs); if added != blot_error::Error.none { deinit(index); return null,added; } blot_support_pooled_map::insert(index.first_exit,node.a,index.exits.items.len - 1,ordinal_slots); }
    } return index,blot_error::Error.none;
}
fn deinit(index: Index&) { if index.owner_id == 0 { return; } blot_support_pooled_map::deinit(index.merges,ordinal_slots); blot_support_pooled_map::deinit(index.positions,position_slots); blot_support_pooled_map::deinit(index.first_exit,ordinal_slots); blot_support_pooled_map::deinit(index.states,state_slots); blot_support_pooled_buffer::deinit(index.exits,exit_runs); let lease = index.lease; index.owner_id = 0; index.lease = -1; indexes.free(lease); }
fn charge(index: Index&,query: Query&,depth: i64) -> bool { if query.remaining == 0 || index.remaining == 0 || depth > 128 { return false; } query.remaining--; index.remaining--; return true; }
recursive fn expression(index: Index&,id: u32,query: Query&,depth: i64) -> blot_support::Option<u32>,Error {
    if !charge(index,query,depth) || id == 0 { return blot_support::none<u32>(),blot_error::Error.none; } let node = index.module.node(id); if node.tag != blot_check_core::Tag.reference { return blot_support::none<u32>(),blot_error::Error.none; } let reference = index.module.reference(id); if reference.unit != 0 && reference.unit != index.module.unit { return blot_support::none<u32>(),blot_error::Error.none; } return binding(index,reference.binding,query,depth + 1);
}
recursive fn binding(index: Index&,id: u32,query: Query&,depth: i64) -> blot_support::Option<u32>,Error {
    if !charge(index,query,depth) { return blot_support::none<u32>(),blot_error::Error.none; } if query.hypothesis.present && id == query.hypothesis.value.iteration { return blot_support::some(query.hypothesis.value.anchor),blot_error::Error.none; } let source = index.module.binding(id); if source.kind == blot_reuse_principal_interface::Kind.parameter { return blot_support::some(id),blot_error::Error.none; } if source.kind != blot_reuse_principal_interface::Kind.local { return blot_support::none<u32>(),blot_error::Error.none; }
    if source.initializer != 0 { let node = index.module.node(source.initializer); if node.tag == blot_check_core::Tag.reference { return expression(index,source.initializer,query,depth + 1); } if node.tag == blot_check_core::Tag.update { for selector in index.module.updateSelectors(source.initializer) { if selector.kind == blot_check_core::UpdateKind.index { return expression(index,index.module.updateInfo(source.initializer).root,query,depth + 1); } } } return blot_support::some(id),blot_error::Error.none; }
    let merge_ordinal .= blot_support_pooled_map::get(index.merges,id); if merge_ordinal { let merge = index.module.merges[merge_ordinal]; let left,error = binding(index,merge.then_binding,query,depth + 1); if error != blot_error::Error.none || !left.present { return left,error; } let right,right_error = binding(index,merge.else_binding,query,depth + 1); if right_error != blot_error::Error.none || !right.present { return right,right_error; } if left.value == right.value { return left,blot_error::Error.none; } return blot_support::some(id),blot_error::Error.none; }
    let position .= blot_support_pooled_map::get(index.positions,id); if position { let carry = index.module.loopCarries(position.loop_)[position.ordinal]; let state .= blot_support_pooled_map::get(index.states,carry.iteration); if state && state == State.building { return blot_support::none<u32>(),blot_error::Error.none; } let unchanged,error = invariant(index,position.loop_,position.ordinal); if error != blot_error::Error.none { return blot_support::none<u32>(),error; } if unchanged { return binding(index,carry.incoming,query,depth + 1); } } return blot_support::some(id),blot_error::Error.none;
}
fn laneCharge(index: Index&,query: LaneQuery&,depth: i64) -> bool { if query.remaining == 0 || index.lane_remaining == 0 || depth > 128 { return false; } query.remaining--; index.lane_remaining--; return true; }
fn sameLane(left: Lane,right: Lane) -> bool { left.binding == right.binding && left.field == right.field }
recursive fn laneExpression(index: Index&,id: u32,field: const u8[:],query: LaneQuery&,depth: i64) -> blot_support::Option<Lane>,Error {
    if !laneCharge(index,query,depth) || id == 0 { return blot_support::none<Lane>(),blot_error::Error.none; } let node = index.module.node(id);
    if node.tag == blot_check_core::Tag.reference { let reference = index.module.reference(id); if reference.unit != 0 && reference.unit != index.module.unit { return blot_support::none<Lane>(),blot_error::Error.none; } return laneBinding(index,reference.binding,field,query,depth + 1); }
    if node.tag == blot_check_core::Tag.record_merge { let right = index.module.types.node(index.module.typeOf(node.b)); if right.tag != blot_check_types::Tag.record { return blot_support::none<Lane>(),blot_error::Error.none; } for ordinal in 0..right.b { let name = index.module.fieldSpelling(index.module.types.recordField(right,ordinal).name); if !name.present { return blot_support::none<Lane>(),blot_error::Error.none; } if name.value == field { return laneExpression(index,node.b,field,query,depth + 1); } } return laneExpression(index,node.a,field,query,depth + 1); }
    if node.tag == blot_check_core::Tag.update { let selectors = index.module.updateSelectors(id); for selector in selectors { if selector.kind == blot_check_core::UpdateKind.index { return laneExpression(index,index.module.updateInfo(id).root,field,query,depth + 1); } } var projection_id: u32; if selectors.len != 0 { if selectors[0].kind != blot_check_core::UpdateKind.field { return blot_support::none<Lane>(),blot_error::Error.none; } projection_id = selectors[0].projection; } else { let path = index.module.updatePath(id); if path.len == 0 { return blot_support::none<Lane>(),blot_error::Error.none; } projection_id = path[0]; } let projection = index.module.projection(projection_id); let source = index.module.types.node(projection.source_type); if source.tag != blot_check_types::Tag.record { return blot_support::none<Lane>(),blot_error::Error.none; } let name = index.module.fieldSpelling(projection.field); if !name.present || name.value == field { return blot_support::none<Lane>(),blot_error::Error.none; } return laneExpression(index,index.module.updateInfo(id).root,field,query,depth + 1); }
    return blot_support::none<Lane>(),blot_error::Error.none;
}
recursive fn laneBinding(index: Index&,id: u32,field: const u8[:],query: LaneQuery&,depth: i64) -> blot_support::Option<Lane>,Error {
    if !laneCharge(index,query,depth) { return blot_support::none<Lane>(),blot_error::Error.none; } if id == query.iteration { return query.anchor,blot_error::Error.none; } let source = index.module.binding(id); if source.kind == blot_reuse_principal_interface::Kind.parameter { return blot_support::some(Lane { binding: id,field: field , ..}),blot_error::Error.none; } if source.kind != blot_reuse_principal_interface::Kind.local { return blot_support::none<Lane>(),blot_error::Error.none; }
    if source.initializer != 0 { let node = index.module.node(source.initializer); if node.tag == blot_check_core::Tag.reference || node.tag == blot_check_core::Tag.record_merge || node.tag == blot_check_core::Tag.update { return laneExpression(index,source.initializer,field,query,depth + 1); } return blot_support::some(Lane { binding: id,field: field , ..}),blot_error::Error.none; }
    let ordinal .= blot_support_pooled_map::get(index.merges,id); if ordinal { let merge = index.module.merges[ordinal]; let left,error = laneBinding(index,merge.then_binding,field,query,depth + 1); if error != blot_error::Error.none || !left.present { return left,error; } let right,right_error = laneBinding(index,merge.else_binding,field,query,depth + 1); if right_error != blot_error::Error.none || !right.present { return right,right_error; } if sameLane(left.value,right.value) { return left,blot_error::Error.none; } return blot_support::none<Lane>(),blot_error::Error.none; } return blot_support::some(Lane { binding: id,field: field , ..}),blot_error::Error.none;
}
fn invariantField(index: Index&,loop_: u32,ordinal: i64,field: const u8[:]) -> bool,Error {
    let carry = index.module.loopCarries(loop_)[ordinal]; var incoming = LaneQuery {..}; let anchor,error = laneBinding(index,carry.incoming,field,incoming,0); if error != blot_error::Error.none || !anchor.present { return false,error; } var query = LaneQuery { iteration: carry.iteration,anchor: anchor , ..}; let backedge,backedge_error = laneBinding(index,carry.backedge,field,query,0); if backedge_error != blot_error::Error.none || !backedge.present { return false,backedge_error; } if !sameLane(backedge.value,anchor.value) { return false,blot_error::Error.none; }
    var cursor = blot_support::none<i64>(); let first .= blot_support_pooled_map::get(index.first_exit,loop_); if first { cursor = blot_support::some<i64>(first); }
    while cursor.present { let exit = index.exits.items[cursor.value]; if !laneCharge(index,query,0) { return false,blot_error::Error.none; } let arguments = index.module.breakValues(exit.node); if ordinal >= arguments.len { return false,blot_error::Error.none; } let lane,lane_error = laneExpression(index,arguments[ordinal],field,query,0); if lane_error != blot_error::Error.none || !lane.present { return false,lane_error; } if !sameLane(lane.value,anchor.value) { return false,blot_error::Error.none; } cursor = exit.next; } return true,blot_error::Error.none;
}
fn canonical(index: Index&,id: u32) -> blot_support::Option<u32>,Error { var query = Query {..}; return binding(index,id,query,0); }
recursive fn invariant(index: Index&,loop_: u32,ordinal: i64) -> bool,Error {
    let carry = index.module.loopCarries(loop_)[ordinal]; let state .= blot_support_pooled_map::get(index.states,carry.iteration); if state { return state == State.invariant,blot_error::Error.none; } if index.active >= 64 { return false,blot_error::Error.none; } index.active++; blot_support_pooled_map::insert(index.states,carry.iteration,State.building,state_slots); let result,error = prove(index,loop_,ordinal);
    if error != blot_error::Error.none { blot_support_pooled_map::remove(index.states,carry.iteration,state_slots); index.active--; return false,error; } let completed .= blot_support_pooled_map::get(index.states,carry.iteration); assert(completed); completed = State.changed; if result { completed = State.invariant; } index.active--; return result,blot_error::Error.none;
}
fn prove(index: Index&,loop_: u32,ordinal: i64) -> bool,Error {
    let carry = index.module.loopCarries(loop_)[ordinal]; var incoming = Query {..}; let anchor,error = binding(index,carry.incoming,incoming,0); if error != blot_error::Error.none || !anchor.present { return false,error; } var query = Query { hypothesis: blot_support::some(Hypothesis { iteration: carry.iteration,anchor: anchor.value , ..}) , ..}; let backedge,backedge_error = binding(index,carry.backedge,query,0); if backedge_error != blot_error::Error.none || !backedge.present { return false,backedge_error; } if backedge.value != anchor.value { return false,blot_error::Error.none; }
    var cursor = blot_support::none<i64>(); let first .= blot_support_pooled_map::get(index.first_exit,loop_); if first { cursor = blot_support::some<i64>(first); } while cursor.present { let exit = index.exits.items[cursor.value]; if !charge(index,query,0) { return false,blot_error::Error.none; } let arguments = index.module.breakValues(exit.node); if ordinal >= arguments.len { return false,blot_error::Error.none; } let value,value_error = expression(index,arguments[ordinal],query,0); if value_error != blot_error::Error.none || !value.present { return false,value_error; } if value.value != anchor.value { return false,blot_error::Error.none; } cursor = exit.next; } return true,blot_error::Error.none;
}
