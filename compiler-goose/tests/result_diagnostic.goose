// Published diagnostic text owns its bytes before scratch/Frame cleanup.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.core_backend;
import backend.result_owner;
import driver.compile_workspace;
fn main() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);let workspace=frame.borrow();assert(workspace);
 let sites=blot_backend_allocation_emission::owned_sites.alloc_slice(1);sites[0]=blot_backend_allocation_emission::Site{unit:7,emissions:2,..};workspace.allocation_snapshot.sites=sites;workspace.allocation_snapshot.omitted=3;
 let headers=blot_backend_startup_emission_facts::header_runs.alloc_slice(1);headers[0]=blot_backend_startup_emission_facts::Header{function:11,origin:blot_backend_startup_emission_facts::Kind.named,unit:7,identity:4,..};workspace.startup_snapshot.headers=headers;
 let events=blot_backend_startup_emission_facts::event_runs.alloc_slice(1);events[0]=blot_backend_startup_emission_facts::Event{kind:blot_backend_startup_emission_facts::EventKind.direct_call,target:13,..};workspace.startup_snapshot.events=events;
 var builder=blot_reuse_dispatch_explanation::Builder{};let operation,error=builder.ownText("dispatch");assert(error==blot_error::Error.none);let explanation,error=builder.finish(blot_support::some<const u8[:]>(operation),blot_support::none<const u8[:]>());assert(error==blot_error::Error.none);workspace.explanation=blot_reuse_dispatch_explanation::canonicalOwned(explanation);builder.deinit();
 let owner,error=blot_backend_result_owner::init();assert(error==blot_error::Error.none);
 var result=blot_backend_core_backend::Result{active:true,output_owner:owner,..};
 result.allocation_emission .=workspace.allocation_snapshot;result.startup_observation .=workspace.startup_snapshot;result.explanation .=workspace.explanation;
 var text:u8[>..<]=[];text.append("entry detail");
 let location=blot_backend_core_backend::Diagnostic{unit:7,span:blot_check_core::Span{3,9},code:blot_check_diagnostic_code::Code.entry_type,related:blot_support::some(blot_eval_core_eval::SourceLocation{unit:8,span:blot_check_core::Span{4,6}}),..};
 assert(blot_backend_core_backend::publishResultDiagnostic(result,location,text)==blot_error::Error.none);
 text.clear();text.append("changed scratch");assert(result.diagnostic.present && result.diagnostic.value.detail=="entry detail" && result.owned_message.items=="entry detail");
 assert(blot_backend_core_backend::detachResult(result)==blot_error::Error.none && result.detached);
 assert(blot_backend_core_backend::detachResult(result)==blot_error::Error.none);
 assert(workspace.allocation_snapshot.sites.len==0 && workspace.startup_snapshot.headers.len==0 && !workspace.explanation.operation.present);
 assert(frame.release()==blot_error::Error.none);
 let allocation .=result.allocation_emission;let startup .=result.startup_observation;let explanation .=result.explanation;assert(allocation && startup && explanation);
 assert(allocation.sites.len==1 && allocation.sites[0].unit==7 && allocation.omitted==3 && startup.headers.len==1 && startup.headers[0].function==11 && startup.events[0].target==13 && explanation.operation.value=="dispatch");
 assert(result.diagnostic.value.detail=="entry detail" && result.owned_message.items=="entry detail" && result.diagnostic.value.unit==7 && result.diagnostic.value.span.start==3 && result.diagnostic.value.span.end==9 && result.diagnostic.value.related.value.unit==8);
 result.deinit();assert(!owner.valid());
 print("result diagnostic owns text across scratch changes and Frame cleanup");
}
