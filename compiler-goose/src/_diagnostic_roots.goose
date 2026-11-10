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
