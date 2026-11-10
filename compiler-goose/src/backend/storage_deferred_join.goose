// Neutral copy pairs retain checked edges until their physical carrier is known.
namespace blot_backend_storage_deferred_join;
import .runtime_code;
import .wasm;
import .wasm_scope_outline;
import support.option;
import support.pooled_buffer;
import support.error;
type Error = blot_error::Error;
type Local = blot_backend_runtime_code::Local;
struct Holes { storage: i64[:] = default<i64[:]>(),items: i64[:] = default<i64[:]>() }
reusable[] var hole_runs: i64[>..] = [];
fn reserve(holes: Holes&,minimum: i64) -> Error { blot_support_pooled_buffer::ensure(holes,minimum,hole_runs) }
fn clear(holes: Holes&) { blot_support_pooled_buffer::clear(holes); }
fn deinit(holes: Holes&) { blot_support_pooled_buffer::deinit(holes,hole_runs); }
struct Lane { first: Local,carrier: blot_support::Option<Local> = blot_support::none<Local>(),holes: Holes = Holes {..} }
reusable[] var lane_runs: Lane[>..] = [];
struct Join { entry_locals: i64,edges: i64 = 0,lanes: Lane[:] = default<Lane[:]>() }
fn registered(join:Join)->Join {
 if join.lanes.len==0 {return Join{entry_locals:join.entry_locals,edges:join.edges,..};}
 let lanes=lane_runs.realloc_slice(join.lanes,join.lanes.len);assert(blot_support::same_slice_identity(lanes,join.lanes));return Join{entry_locals:join.entry_locals,edges:join.edges,lanes:lanes};
}
fn init<M>(code: blot_backend_runtime_code::Code<M>) -> Join { let module .= code.module; return Join { entry_locals: module.parameters(code.function).len + module.locals(code.function).len , ..}; }
fn deinit(join: Join&) { for &lane in join.lanes { lane.holes.deinit(); } if join.lanes.len != 0 { lane_runs.free_slice(join.lanes); } join.lanes=default<Lane[:]>(); join.edges = 0; }
fn materialize<M>(lane: Lane&,code: blot_backend_runtime_code::Code<M>&,context: blot_backend_wasm_scope_outline::Context&) -> Error {
    if lane.carrier.present { return blot_error::Error.none; } let carrier,error = code.temp(); if error != blot_error::Error.none { return error; }
    for index in lane.holes.items { let patched = context.patchCopy(code.function,index,lane.first.id,carrier.id); if patched != blot_error::Error.none { return patched; } }
    lane.holes.clear(); lane.carrier = blot_support::some(carrier); return blot_error::Error.none;
}
fn add<M>(join: Join&,code: blot_backend_runtime_code::Code<M>&,context: blot_backend_wasm_scope_outline::Context&,words: const Local[:]) -> Error {
    if join.edges == 0 { join.lanes = lane_runs.alloc_slice(words.len); for word,index in words { join.lanes[index] = Lane { first: word , ..}; } }
    if words.len != join.lanes.len { return blot_error::Error.invalid_outline; }
    for &lane,index in join.lanes {
        let incoming = words[index];
        if join.edges != 0 && (lane.first.id != incoming.id || lane.first.id >= join.entry_locals) { let error = materialize(lane,code,context); if error != blot_error::Error.none { return error; } }
        if lane.carrier.present { let error = code.set(lane.carrier.value,incoming); if error != blot_error::Error.none { return error; } }
        else { let reserved = lane.holes.reserve(lane.holes.items.len + 1); if reserved != blot_error::Error.none { return reserved; } let position,error = context.reserveCopy(code.function); if error != blot_error::Error.none { return error; } let length = lane.holes.items.len; let slots=hole_runs.realloc_slice(lane.holes.storage,lane.holes.storage.len);slots[length]=position;lane.holes.items=slots[..length+1]; }
    }
    join.edges++; return blot_error::Error.none;
}
fn finish<M,S>(join: Join&,code: blot_backend_runtime_code::Code<M>&,context: blot_backend_wasm_scope_outline::Context&,mutable_words: const S&,fallthrough: bool) -> u64,Error {
    var shared: u64 = 0;
    for &lane in join.lanes {
        if fallthrough || mutable_words.contains(lane.first.id) { let error = materialize(lane,code,context); if error != blot_error::Error.none { return 0,error; } }
        if !lane.carrier.present { for index in lane.holes.items { let error = context.releaseCopy(code.function,index); if error != blot_error::Error.none { return 0,error; } } lane.holes.clear(); shared += join.edges as u64; }
    }
    return shared,blot_error::Error.none;
}
fn word(join: Join,index: i64) -> Local { let lane = join.lanes[index]; if lane.carrier.present { return lane.carrier.value; } return lane.first; }
