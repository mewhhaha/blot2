// The persistent workspace starts without borrowing a caller catalog.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.core_eval;
import support.error;
import support.native;
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
    }
}
