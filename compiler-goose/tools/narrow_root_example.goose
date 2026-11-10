// Temporary narrow diagnostic root for the numeric proof checker.
namespace blot_numeric_probe;
import bootstrap_globals;
import backend.backend_emission;
import backend.core_backend;
import backend.result_publication;
import check.core;
import driver.compile_workspace;
import runtime.runtime_cleanup;
import support.error;
import support.native;
export "probe_numeric" fn numeric() {
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());if error!=blot_error::Error.none {return;}
 let cleanup,cleanup_error=blot_runtime_runtime_cleanup::initPooled(); if cleanup_error!=blot_error::Error.none {return;}
 var owner=blot_backend_backend_emission::Owner { frame: frame, unit_id: 0, function_id: 0, cleanups: cleanup, .. };
 let numeric=blot_backend_backend_emission::prepareNumeric(owner,1); owner.deinit();
 let released=frame.release();assert(released==blot_error::Error.none);
 if numeric!=blot_error::Error.none {return;}
}
