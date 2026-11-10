import bootstrap_globals;
// Match the production traversal of cyclic inactive headers.
import driver.cli;
import driver.cli_workers;
import std;
import check.parameter_patterns;
import eval.type_evidence;
import eval.semantic_evidence_import;
import driver.compile_workspace_backing;
import eval.implementation_evidence;
import support.error;

reusable[] var retained_importers:blot_eval_semantic_evidence_import::RetainedImporter[>..]=[];
fn publishImporter(target:blot_eval_semantic_evidence_import::RetainedImporter&,destination:blot_eval_type_evidence::Store) {target=blot_eval_semantic_evidence_import::initRetained(destination,128,false);}
fn retainedEvidence() {
 var source,error=blot_eval_type_evidence::init();assert(error==blot_error::Error.none);var destination,error=blot_eval_type_evidence::init();assert(error==blot_error::Error.none);
 let id,error=source.intern(blot_eval_type_evidence::Tag.array,3,0,[]);assert(error==blot_error::Error.none);let retained=retained_importers.alloc_slice(1);publishImporter(retained[0],destination);
 let key=retained[0].destination;assert(blot_eval_type_evidence::valid(key));blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();
 let mapped,error=retained[0].tyWithSource(source.view(),id,0);assert(error==blot_error::Error.none && destination.node(mapped).tag==blot_eval_type_evidence::Tag.array && destination.node(mapped).a==3);
 destination.deinit();assert(!blot_eval_type_evidence::valid(key));var next,error=blot_eval_type_evidence::init();assert(error==blot_error::Error.none);let fresh=blot_eval_type_evidence::acquireHandle(next);assert(fresh.lease==key.lease && fresh.generation!=key.generation && !blot_eval_type_evidence::valid(key));retained[0].deinit();retained_importers.free_slice(retained);next.deinit();source.deinit();
}
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
fn patternLeases() {
    assert(!blot_check_parameter_patterns::valid(blot_check_parameter_patterns::Store{}));
    for iteration in 0..32 {
        var store,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
        let view=blot_check_parameter_patterns::checkedView(store);
        var wrong=view;wrong.generation++;assert(!blot_check_parameter_patterns::valid(wrong));
        wrong=view;wrong.lease=0;assert(!blot_check_parameter_patterns::valid(wrong));
        let id,error=store.add(blot_check_parameter_patterns::Node{blot_check_parameter_patterns::Kind.binding,17});assert(error==blot_error::Error.none);
        let span,error=store.saveList([id]);assert(error==blot_error::Error.none);
        assert(view.node(id).a==17 && view.list(span)[0]==id);
        assert(view.nodes() .== store.nodes() && view.extra() .== store.extra());
        store.deinit();assert(!blot_check_parameter_patterns::valid(view));
        var next,error=blot_check_parameter_patterns::initPooled();assert(error==blot_error::Error.none);
        assert(next.lease==view.lease && next.generation!=view.generation && !blot_check_parameter_patterns::valid(view));next.deinit();
    }
}
fn main() {retainedEvidence();
    evidenceLeases();implementationLeases();patternLeases();
    print("proof leases passed: shared headers, owner/generation rejection, release/reuse");
}
