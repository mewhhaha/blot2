// Concrete development entry paths. Selected-root checking is partial only.
namespace blot_diagnostic_roots;
import bootstrap_globals;
import support.error;
import backend.runtime_parallel;
import eval.component_worker;
import reuse.independent_worker;
import driver.project_executor;

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
