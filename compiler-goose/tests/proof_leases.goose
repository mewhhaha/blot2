import bootstrap_globals;
// Match the production traversal of cyclic inactive headers.
import driver.cli;
import driver.cli_workers;
import std;
import eval.type_evidence;
import eval.implementation_evidence;
import support.error;

fn evidenceLeases() {
    for iteration in 0..32 {
        var store,error=blot_eval_type_evidence::init();
        assert(error==blot_error::Error.none);
        let handle=blot_eval_type_evidence::acquireHandle(store);
        assert(blot_eval_type_evidence::valid(handle));
        var wrong=handle;wrong.owner_id=0;
        assert(!blot_eval_type_evidence::valid(wrong));
        wrong=handle;wrong.generation++;
        assert(!blot_eval_type_evidence::valid(wrong));
        wrong=handle;wrong.lease=0;
        assert(!blot_eval_type_evidence::valid(wrong));
        {
            var view=blot_eval_type_evidence::reifyStore(handle);
            assert(view.nodes .== store.nodes);
            assert(view.extra .== store.extra);
            let id,error=view.intern(blot_eval_type_evidence::Tag.array,3,0,[]);
            assert(error==blot_error::Error.none);
            assert(store.node(id).a==3);
            assert(blot_eval_type_evidence::reifyStore(handle).node(id).a==3);
            assert(blot_eval_type_evidence::reifyStore(handle).view().owner_id==handle.owner_id);
            let again=blot_eval_type_evidence::acquireHandle(view);
            assert(again.owner_id==handle.owner_id && again.lease==handle.lease && again.generation==handle.generation);
        }
        store.deinit();
        assert(!blot_eval_type_evidence::valid(handle));
        var replacement,error=blot_eval_type_evidence::init();
        assert(error==blot_error::Error.none);
        let next=blot_eval_type_evidence::acquireHandle(replacement);
        assert(next.lease==handle.lease && next.generation!=handle.generation);
        assert(!blot_eval_type_evidence::valid(handle));
        replacement.deinit();
    }
}
fn implementationLeases() {
    for iteration in 0..32 {
        var store,error=blot_eval_implementation_evidence::initPooled();
        assert(error==blot_error::Error.none);
        let handle=blot_eval_implementation_evidence::acquireHandle(store);
        assert(blot_eval_implementation_evidence::valid(handle));
        var wrong=handle;wrong.owner_id=0;
        assert(!blot_eval_implementation_evidence::valid(wrong));
        wrong=handle;wrong.generation++;
        assert(!blot_eval_implementation_evidence::valid(wrong));
        wrong=handle;wrong.lease=0;
        assert(!blot_eval_implementation_evidence::valid(wrong));
        {
            var view=blot_eval_implementation_evidence::reifyStore(handle);
            assert(view.proofs .== store.proofs);
            assert(view.arguments .== store.arguments);
            view.hits+=7;
            assert(store.hits==7);
            assert(blot_eval_implementation_evidence::reifyStore(handle).view().owner_id==handle.owner_id);
            let again=blot_eval_implementation_evidence::acquireHandle(view);
            assert(again.owner_id==handle.owner_id && again.lease==handle.lease && again.generation==handle.generation);
        }
        store.deinit();
        assert(!blot_eval_implementation_evidence::valid(handle));
        var replacement,error=blot_eval_implementation_evidence::initPooled();
        assert(error==blot_error::Error.none);
        let next=blot_eval_implementation_evidence::acquireHandle(replacement);
        assert(next.lease==handle.lease && next.generation!=handle.generation);
        assert(!blot_eval_implementation_evidence::valid(handle));
        replacement.deinit();
    }
}
fn main() {
    evidenceLeases();implementationLeases();
    print("proof leases passed: shared headers, owner/generation rejection, release/reuse");
}
