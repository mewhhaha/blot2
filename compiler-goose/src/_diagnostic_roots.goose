// Concrete development entry paths. Selected-root checking is partial only.
namespace blot_diagnostic_roots;
import bootstrap_globals;
import support.error;
import backend.runtime_parallel;
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
