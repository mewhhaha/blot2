import bootstrap_globals;
// Match the production traversal of cyclic inactive headers.
import driver.cli;
import driver.cli_workers;
import std;
import check.parameter_patterns;
import eval.type_evidence;
import eval.semantic_evidence_import;
import reuse.constant_receipt_reuse;
import driver.compile_workspace_backing;
import eval.implementation_evidence;
import support.error;
import driver.compile_workspace;
import reuse.code_artifacts;
import reuse.principal_inputs;
import reuse.principal_archive;
import reuse.dependency_payload;
import backend.result_publication;
import support.native;


reusable[] var retained_importers:blot_eval_semantic_evidence_import::RetainedImporter[>..]=[];
fn publishImporter(target:blot_eval_semantic_evidence_import::RetainedImporter&,destination:blot_eval_type_evidence::Store) {target=blot_eval_semantic_evidence_import::initRetained(destination,128,false);}
recursive fn replayQueryCycle(value:const blot_reuse_constant_receipt::Query&,depth:i64) {let current=blot_reuse_constant_receipt_reuse::replayQueryHeader(value);if depth!=0 {replayQueryCycle(current,depth-1);}let judgment .=current.judgment;if judgment {assert(judgment.allocation_index>=0);}}
fn replayQueryOwnership() {
 let mappings=[blot_eval_type_evidence::Mapping{variable:7,evidence:3}];let selected=[blot_check_core::BindingRef{1,9}];
 var judgment=blot_reuse_constant_receipt::Judgment{kind:blot_reuse_constant_receipt::JudgmentKind.match_,unit:1,source:3,inputs:blot_reuse_constant_receipt::Inputs{types:mappings[..],..},selected:selected[..],..};
 let template=blot_reuse_constant_receipt::Query{kind:blot_reuse_constant_receipt::QueryKind.judgment,input:3,judgment:judgment,..};
 let source_value,error=template.clone();assert(error==blot_error::Error.none && source_value);let source:blot_reuse_constant_receipt::Query& =source_value;
 let owned_value,error=source.clone();assert(error==blot_error::Error.none && owned_value);let owned:blot_reuse_constant_receipt::Query& =owned_value;
 replayQueryCycle(owned,3);let source_slot=source.allocation_index;let clone_slot=owned.allocation_index;assert(source_slot!=clone_slot);let source_judgment .=source.judgment;let clone_judgment .=owned.judgment;assert(source_judgment && clone_judgment && source_judgment .!= clone_judgment);let source_judgment_slot=source_judgment.allocation_index;let clone_judgment_slot=clone_judgment.allocation_index;assert(source_judgment_slot!=clone_judgment_slot);
 var current=blot_reuse_constant_receipt_reuse::replayQueryHeader(owned);current.input=17;current.selected=19;current.allocation_index=source_slot;
 blot_reuse_constant_receipt_reuse::setReplayedQuery(owned,current);assert(owned.allocation_index==clone_slot && source.allocation_index==source_slot && source.input==3 && owned.input==17 && owned.selected==19 && owned.judgment .== clone_judgment && source.judgment .== source_judgment);
 owned.destroy();assert(source.allocation_index==source_slot && source_judgment.allocation_index==source_judgment_slot && source_judgment.inputs.types[0].variable==7 && source_judgment.selected[0].binding==9);
 let next_value,error=source.clone();assert(error==blot_error::Error.none && next_value);let next:blot_reuse_constant_receipt::Query& =next_value;assert(next.allocation_index==clone_slot);source.destroy();let next_judgment .=next.judgment;assert(next_judgment && next_judgment.inputs.types[0].evidence==3 && next_judgment.selected[0].binding==9);next.destroy();
 let scalar=blot_reuse_constant_receipt::Query{kind:blot_reuse_constant_receipt::QueryKind.entry,input:5,..};let a_value,error=scalar.clone();assert(error==blot_error::Error.none && a_value);let a:blot_reuse_constant_receipt::Query& =a_value;let b_value,error=a.clone();assert(error==blot_error::Error.none && b_value);let b:blot_reuse_constant_receipt::Query& =b_value;let b_slot=b.allocation_index;var result=blot_reuse_constant_receipt_reuse::replayQueryHeader(b);result.selected=23;result.allocation_index=a.allocation_index;blot_reuse_constant_receipt_reuse::setReplayedQuery(b,result);assert(b.allocation_index==b_slot && b.judgment==null && a.input==5 && b.selected==23);a.destroy();b.destroy();
}
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
fn registeredWorkspaceSources() {
 let owner=blot_native::fresh_owner_id();var frame,error=blot_compile_workspace::create(owner);assert(error==blot_error::Error.none);
 let workspace .=frame.borrow();assert(workspace);
 var catalog,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let source,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(catalog,1);assert(error==blot_error::Error.none);source[0]=blot_check_core::Module{unit:1,..};
 assert(blot_backend_result_publication::stageInputs(workspace.publication_owner,source,catalog,[catalog],[])==blot_error::Error.none);
 let held,error=blot_backend_result_publication::registeredInputUnits(workspace.publication_owner);assert(error==blot_error::Error.none);
 blot_compile_workspace::backing_query_state.gate.units=held;
 workspace.metadata.pools=blot_support::Option<blot_reuse_code_artifacts::Pools>{true,default<blot_reuse_code_artifacts::Pools>()};workspace.metadata.pools.value.generation=19;
 let pools:const blot_reuse_code_artifacts::Pools& =blot_reuse_code_artifacts::registeredPools(workspace.metadata);assert(pools .==workspace.metadata.pools.value && pools.generation==19);workspace.metadata.pools.value.generation=23;assert(pools.generation==23);
 let units=blot_compile_workspace::queryUnits(blot_compile_workspace::backing_query_state);assert(units.len==1 && units[0].unit==1 && blot_support::same_slice_identity(units,held));
 blot_compile_workspace::backing_principal_state.gate.units=held;let principal=blot_compile_workspace::principalUnits(blot_compile_workspace::backing_principal_state);assert(blot_support::same_slice_identity(principal,units));
 var local_state=copy(blot_compile_workspace::backing_query_state);local_state.old=workspace.capture;let query_pools .=blot_eval_completed_specialization_query::sourcePools(local_state);assert(query_pools .==pools && query_pools.generation==23);
 assert(frame.release()==blot_error::Error.none);catalog.deinit();
}
fn main() {replayQueryOwnership();retainedEvidence();registeredWorkspaceSources();
    evidenceLeases();implementationLeases();patternLeases();
    print("proof leases passed: shared headers, owner/generation rejection, release/reuse");
}
