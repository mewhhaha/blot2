// Physical representations and substitutions precede their lazy semantic bridge.
namespace blot_backend_backend_representations;
import check.core;
import .layout;
import .layout_bridge;
import eval.type_evidence;
import eval.instance_arguments;
import reuse.substitution_keys;
import support.error;
struct State {
    store: blot_backend_layout::Store&,connection: blot_backend_layout_bridge::Store&,connection_bound: bool = false,
    row_keys: blot_reuse_substitution_keys::Store&,template_keys: blot_reuse_substitution_keys::Store&,static_keys: blot_reuse_substitution_keys::Store&,instance_arguments: blot_eval_instance_arguments::Store&,
}
fn init(state: State&,units: const blot_check_core::Module[:]) -> blot_error::Error {
    let initialized = state.store.reset(); if initialized != blot_error::Error.none { return initialized; } state.store.opaque_sources = units; state.store.closed.units = units;
    for source in units { let error = state.store.record_names.add(state.store.opaque_sources,source); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return blot_error::Error.declined; } }
    resetCaches(state); return blot_error::Error.none;
}
fn initEmpty(state:State&)->blot_error::Error {
    let initialized=state.store.reset();if initialized!=blot_error::Error.none {return initialized;}
    state.store.opaque_sources=default<const blot_check_core::Module[:]>();state.store.closed.units=default<const blot_check_core::Module[:]>();
    resetCaches(state);return blot_error::Error.none;
}
fn resetCaches(state:State&) {
    state.row_keys.deinit(); state.template_keys.deinit(); state.static_keys.deinit(); state.instance_arguments.deinit(); state.instance_arguments = blot_eval_instance_arguments::init(state.instance_arguments.values,state.instance_arguments.spans);
    state.connection_bound = false;
}
fn fromStore(store: blot_backend_layout::Store&,connection: blot_backend_layout_bridge::Store&,row_keys: blot_reuse_substitution_keys::Store&,template_keys: blot_reuse_substitution_keys::Store&,static_keys: blot_reuse_substitution_keys::Store&,instance_arguments: blot_eval_instance_arguments::Store&) -> State {
    State { store,connection,false,row_keys,template_keys,static_keys,instance_arguments }
}
fn deinit(state: State&) { if state.connection_bound { state.connection.deinit(); } state.connection_bound = false; state.store.deinit(); state.row_keys.deinit(); state.template_keys.deinit(); state.static_keys.deinit(); state.instance_arguments.deinit(); }
fn representationBridge(state: State&,evidence: blot_eval_type_evidence::Store&) -> blot_backend_layout_bridge::Store&,blot_error::Error {
    if !state.connection_bound { let error = state.connection.bind(state.store,evidence); if error != blot_error::Error.none { return state.connection,error; } state.connection_bound = true; }
    return state.connection,blot_error::Error.none;
}
fn toEvidence(state: State&,evidence: blot_eval_type_evidence::Store&,id: u32) -> u32,blot_error::Error { let bridge,error = representationBridge(state,evidence); if error != blot_error::Error.none { return 0,error; } return bridge.toEvidence(id); }
fn fromEvidence(state: State&,evidence: blot_eval_type_evidence::Store&,id: u32) -> u32,blot_error::Error { let bridge,error = representationBridge(state,evidence); if error != blot_error::Error.none { return 0,error; } return bridge.fromEvidence(id); }
fn rowToEvidence(state: State&,evidence: blot_eval_type_evidence::Store&,id: u32) -> u32,blot_error::Error { let bridge,error = representationBridge(state,evidence); if error != blot_error::Error.none { return 0,error; } return bridge.rowToEvidence(id); }
fn rowFromEvidence(state: State&,evidence: blot_eval_type_evidence::Store&,id: u32) -> u32,blot_error::Error { let bridge,error = representationBridge(state,evidence); if error != blot_error::Error.none { return 0,error; } return bridge.rowFromEvidence(id); }
