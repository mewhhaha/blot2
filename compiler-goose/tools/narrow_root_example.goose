// Temporary narrow diagnostic root for the numeric proof checker.
namespace squid_numeric_probe;
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
 var frame,error=squid_compile_workspace::create(squid_native::fresh_owner_id());if error!=squid_error::Error.none {return;}
 let cleanup,cleanup_error=squid_runtime_runtime_cleanup::initPooled(); if cleanup_error!=squid_error::Error.none {return;}
 var owner=squid_backend_backend_emission::Owner { frame: frame, unit_id: 0, function_id: 0, cleanups: cleanup, .. };
 let numeric=squid_backend_backend_emission::prepareNumeric(owner,1); owner.deinit();
 let released=frame.release();assert(released==squid_error::Error.none);
 if numeric!=squid_error::Error.none {return;}
}
