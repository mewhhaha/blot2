// Archive captures own live metadata; inactive readers carry no sentinel reference.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace_backing;
import reuse.artifact_capture;
import support.error;
import backend.backend_checkpoint;
import reuse.optimized_archive;
import driver.compile_workspace;
fn optimizerHeader()->i64 {
 var producer,error=blot_backend_optimized_bodies::initPooled();assert(error==blot_error::Error.none);
 assert(producer.signatures.push(blot_backend_optimized_bodies::Signature{blot_backend_optimized_bodies::copyTypes([blot_backend_runtime_ir::VT_i32]),blot_backend_runtime_ir::VT_i32})==blot_error::Error.none);
 assert(producer.imports.push(blot_backend_optimized_bodies::Import{blot_backend_optimized_bodies::copyBytes("module"),blot_backend_optimized_bodies::copyBytes("import"),0})==blot_error::Error.none);
 let encoded,error=blot_reuse_optimized_archive::encode([0;32],producer);assert(error==blot_error::Error.none);producer.deinit();
 let decoded,error=blot_reuse_optimized_archive::decode([0;32],encoded);blot_reuse_dependency_format::release(encoded);assert(error==blot_error::Error.none);
 return blot_backend_backend_checkpoint::publishOptimizer(decoded);
}
fn optimizerPublication() {
 let header=optimizerHeader();var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 let capture:blot_backend_optimized_bodies::Capture& =blot_backend_backend_checkpoint::optimizer_headers[header];assert(capture.valid() && capture.signatures.items.len==1 && capture.signatures.items[0].parameters[0]==blot_backend_runtime_ir::VT_i32 && capture.imports.items[0].module=="module" && capture.imports.items[0].name=="import");capture.deinit();blot_backend_backend_checkpoint::optimizer_headers.free(header);
}
fn main() {optimizerPublication();
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
