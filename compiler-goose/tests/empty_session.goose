// The persistent workspace starts without borrowing a caller catalog.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.core_eval;
import driver.compile_workspace;
import support.error;
import support.native;
fn inspectWorkspace(frame:blot_compile_workspace::Frame) {
    let workspace .=frame.borrow();assert(workspace!=null);
    assert(workspace.generator.evaluator.units.len==0 && workspace.capture.metadata().validContext());
    let key=blot_backend_backend_static_data::SerializedKey{1,2};assert(workspace.generator.static_data.cache.insert(key,17)==blot_error::Error.none);let stored=workspace.generator.static_data.cache.get(key);assert(stored && stored==17);
}
fn workspaceLifecycle() {
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());
    inspectWorkspace(frame);assert(frame.release()==blot_error::Error.none && !frame.valid());
}
fn main() {
    var previous:u64=0;
    for cycle in 0..4 {
        let allocation_owner=blot_native::fresh_owner_id();
        let session,error=blot_eval_core_eval::initOwnedEmptySession(allocation_owner);
        assert(error==blot_error::Error.none && session);
        assert(session.units.len==0 && session.binding_offsets.len==0 && session.node_offsets.len==0 && session.slots.len==0);
        assert(session.allocation_owner==allocation_owner && session.session_owner_slot!=0);
        let generation=session.session_owner_generation;
        assert(generation>previous);
        previous=generation;
        blot_eval_core_eval::deinitOwnedSession(session);
        workspaceLifecycle();
    }
}
