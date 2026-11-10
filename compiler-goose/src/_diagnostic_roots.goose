// Concrete development entry paths. Selected-root checking is partial only.
namespace blot_diagnostic_roots;
import bootstrap_globals;
import support.error;
import backend.runtime_parallel;
import backend.scoped_backend;
import driver.compile_workspace;
import eval.component_worker;
import reuse.independent_worker;
import driver.project_executor;
import reuse.restart_cache;
import reuse.zig_project_server;
import execution_policy;
import support.io;
import support.option;
import backend.core_backend;
import backend.result_publication;
import check.core;
import reuse.code_artifacts;

export "probe_runtime" fn runtime() {
 var output:u8[>..<]=[];
 let error=blot_backend_runtime_parallel::executePacket([],output);
 if error!=blot_error::Error.none {return;}
}
export "probe_semantic" fn semantic() {
 var output:u8[>..<]=[];
 let error=blot_eval_component_worker::executePacket([],output);
 if error!=blot_error::Error.none {return;}
}
export "probe_check" fn check() {
 var output:u8[>..<]=[];
 let error=blot_project_executor::executeCheckPacket([],output);
 if error!=blot_error::Error.none {return;}
}
export "probe_lower" fn lower() {
 var output:u8[>..<]=[];
 let error=blot_project_executor::executeLowerPacket([],output);
 if error!=blot_error::Error.none {return;}
}
export "probe_independent" fn independent() {
 var output:u8[>..<]=[];
 let error=blot_reuse_independent_call_proof::executePacket([],output);
 if error!=blot_error::Error.none {return;}
}

// The server entry uses the real executor without CLI worker-dispatch branches.
export "probe_server" fn server() {
 var cache=blot_support::none<u8[:]>();let root,error=blot_reuse_restart_cache::root();if error==blot_error::Error.none {cache=root;}
 var cache_root=blot_support::none<const u8[:]>();if cache.present {cache_root=blot_support::some<const u8[:]>(cache.value[..]);}
 var executor=blot_project_executor::init();
 let error=blot_reuse_zig_project_server::runWithPolicy(executor,blot_io::Reader{0},blot_io::Writer{1},[0;32],cache_root,blot_execution_policy::Policy{..});
 executor.deinit();if cache.present {blot_reuse_restart_cache::releaseRoot(cache.value);}
}

// Packet construction/serialization/reply checking only; this is not a runtime law.
export "probe_executor" fn executor() {
 var worker=blot_project_executor::init();let source=blot_reuse_project::Project{..};
 var engine,error=blot_reuse_project_check::initEngine(source,blot_check_check::PrivateExecution{..},blot_reuse_project_check::Editor.none,false);if error!=blot_error::Error.none {worker.deinit();return;}
 let order:u32[0]=default<u32[0]>();var jobs:blot_reuse_project_check::ParallelJob[0]=default<blot_reuse_project_check::ParallelJob[0]>();
 let counts,error=worker.runProjectChecks(engine,order[..],1,jobs[..]);engine.deinit();worker.deinit();if error!=blot_error::Error.none {return;}
}

// Completion reply schema checking only; no query or runtime qualification.
export "probe_metadata" fn metadata() {
 var bytes:u8[>..]=[];let error=blot_reuse_zig_project_server::encodeMetadata(default<blot_reuse_zig_project_server::CompletionReply>(),bytes);if error!=blot_error::Error.none {return;}
}

// Traverses the scoped backend without loading/checking a source project.
// Empty Core is deliberate: this is type checking, never a runtime test.
export "probe_scoped" fn scoped() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);let units=blot_backend_result_publication::module_runs.alloc_slice(1);units[0]=blot_check_core::Module{unit:1,..};
 let result,error=blot_backend_scoped_backend::compileWithOptions(workspace,units,1,blot_backend_scoped_backend::CompileOptions{..});if error==blot_error::Error.none {var owned=result;owned.deinit();}
 let released=frame.release();assert(released==blot_error::Error.none);blot_backend_result_publication::module_runs.free_slice(units);
}

// Preparation traversal only. Inputs are deliberately unstaged: never execute.
export "probe_prepare" fn prepare() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);
 var run=blot_backend_core_backend::CompileRun{workspace:workspace,entry:1,options:blot_backend_core_backend::CompileOptions{..},..};
 let error=blot_backend_core_backend::prepare(run);
 if error==blot_error::Error.none {
  var stamp_entries:blot_reuse_code_artifacts::ModuleStampEntry[>..<]=[];var memo=blot_reuse_code_artifacts::ModuleStamps{storage:stamp_entries,..};
  let bound=memo.bindValidatedSources(run.stamp_sources);if bound==blot_error::Error.none {memo.compare_contents=true;memo.validate=run.options.validate_pins;let prepared=blot_backend_core_backend::finishPreparation(run,false,memo);}
  memo.deinit();
 }
 run.deinit();
 let released=frame.release();assert(released==blot_error::Error.none);
}

// Full backend routing without a source project. Unstaged Core: never execute.
export "probe_compile" fn compile() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);let units=blot_backend_result_publication::module_runs.alloc_slice(1);units[0]=blot_check_core::Module{unit:1,..};
 let result,error=blot_backend_core_backend::compileWithOptions(workspace,units,1,blot_backend_core_backend::CompileOptions{..});if error==blot_error::Error.none {var owned=result;owned.deinit();}
 let released=frame.release();assert(released==blot_error::Error.none);blot_backend_result_publication::module_runs.free_slice(units);
}

// Diagnostic rendering traversal on deliberately uninitialized evidence; never execute.
export "probe_entry_display" fn entry_display() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);var text:u8[>..<]=[];var display=blot_backend_core_backend::EntryDisplay{workspace.generator,text};
 let printed,error=blot_backend_core_backend::ty(display,0,64);
 let body=default<blot_check_core::Body>();let header=default<blot_eval_core_eval::SourceInterface>();
 let declined=blot_backend_core_backend::declineEntryInterface(workspace.generator,1,body,header);
 let released=frame.release();assert(released==blot_error::Error.none);
}


// Check-only diagnostic probes. These intentionally invalid, unstaged fixtures
// type-check later backend phases. Never execute these roots.
export "probe_assemble" fn assemble() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);
 var run=blot_backend_core_backend::CompileRun{workspace:workspace,entry:1,options:blot_backend_core_backend::CompileOptions{..},..};
 let compiled,error=blot_backend_core_backend::assemble(run);
 run.deinit();var result=compiled;result.deinit();let released=frame.release();assert(released==blot_error::Error.none);
}

fn recordArtifactScope(run:blot_backend_core_backend::CompileRun&,result:blot_backend_core_backend::Result&)->blot_backend_core_backend::ArtifactCounts,blot_error::Error {
 var stamp_entries:blot_reuse_code_artifacts::ModuleStampEntry[>..<]=[];var memo=blot_reuse_code_artifacts::ModuleStamps{storage:stamp_entries,..};
 let counts,error=blot_backend_core_backend::recordArtifact(run,result,memo);memo.deinit();return counts,error;
}
export "probe_record_artifact" fn record_artifact() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);
 var run=blot_backend_core_backend::CompileRun{workspace:workspace,entry:1,options:blot_backend_core_backend::CompileOptions{..},..};
 var result=blot_backend_core_backend::emptyResult(workspace);
 let counts,error=recordArtifactScope(run,result);if error==blot_error::Error.none {let finished=blot_backend_core_backend::finishArtifact(run,result,counts);}
run.deinit();result.deinit();let released=frame.release();assert(released==blot_error::Error.none);
}

export "probe_publish" fn publish() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);
 var run=blot_backend_core_backend::CompileRun{workspace:workspace,entry:1,options:blot_backend_core_backend::CompileOptions{..},..};
 var result=blot_backend_core_backend::emptyResult(workspace);
 let error=blot_backend_core_backend::publish(run,result,blot_backend_core_backend::ModuleStamps{..});
 run.deinit();result.deinit();let released=frame.release();assert(released==blot_error::Error.none);
}

export "probe_detach_result" fn detach_result() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);var result=blot_backend_core_backend::emptyResult(workspace);
 let error=blot_backend_core_backend::detachResult(result);
 result.deinit();let released=frame.release();assert(released==blot_error::Error.none);
}

export "probe_emit" fn emit() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);var run=blot_backend_core_backend::CompileRun{workspace:workspace,entry:1,options:blot_backend_core_backend::CompileOptions{..},..};
 let emitted,error=blot_backend_core_backend::emit(run);run.deinit();match emitted {diagnostic failure=>{var result=failure.value;result.deinit();},complete=>{}}
let released=frame.release();assert(released==blot_error::Error.none);
}
export "probe_observe" fn observe() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);var run=blot_backend_core_backend::CompileRun{workspace:workspace,entry:1,options:blot_backend_core_backend::CompileOptions{..},..};var result=blot_backend_core_backend::emptyResult(workspace);
 let error=blot_backend_core_backend::observe(run,result);run.deinit();result.deinit();let released=frame.release();assert(released==blot_error::Error.none);
}

// Source-interface traversal only; unstaged Core, never execute.
export "probe_source_interface" fn source_interface() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);
 let header,error=workspace.generator.evaluator.sourceInterface(blot_check_core::BindingRef{1,1});
 let released=frame.release();assert(released==blot_error::Error.none);
}

// Diagnostic publication and unit-use cache only; unstaged Core, never execute.
export "probe_generator_diagnostic" fn generator_diagnostic() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let workspace=frame.borrow();assert(workspace);
 let target,error=blot_backend_core_backend::associatedTarget(workspace.generator,1,blot_check_types::NominalIdentity{0,0},0,blot_check_types::Operator.none);
 let uses,error=blot_backend_core_backend::unitUses(workspace.generator,1,blot_backend_unit_index::Need{..});
 blot_backend_resolved_body::deinit();
 let released=frame.release();assert(released==blot_error::Error.none);
}
