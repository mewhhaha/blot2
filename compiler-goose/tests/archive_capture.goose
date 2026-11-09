// Archive captures own live metadata; inactive readers carry no sentinel reference.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace_backing;
import reuse.artifact_capture;
import support.error;
fn main() {
    var factory=blot_reuse_artifact_capture::Factory{allocation_owner:blot_native::fresh_owner_id()};
    for cycle in 0..4 {
        let capture,token,error=factory.createArchiveCapture();assert(error==blot_error::Error.none && capture!=null && token!=0);
        assert(capture.metadata().validContext() && !capture.metadata().pools.present && capture.executable_queries.records.len==0);
        capture.metadata().pools=blot_support::some(default<blot_reuse_code_artifacts::Pools>());
        assert(capture.metadata().pools.present);
        factory.destroyArchiveCapture(token);
        blot_compile_workspace::clearBacking();
        blot_compile_workspace::resetBackingDescriptors();
    }
    print("archive capture passed: live metadata publication, release, inactive readers and backing reset");
}
