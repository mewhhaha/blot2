// Completion probes read an owned revision image without retaining lexer scratch.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.completion_probe;
import reuse.revision_inputs;
import reuse.source_overlays;
import reuse.project;
import support.error;
fn main() {
    for cycle in 0..3 {
        var source:u8[>..]=[];source.append("const value = hel\n");
        let supplied=[blot_reuse_source_overlays::Source{path:"/tmp/completion-probe.blot",contents:blot_support::some<const u8[:]>(source[..])}];
        var snapshot,error=blot_reuse_revision_inputs::initWithSources(blot_reuse_project::Options{..},supplied[..]);assert(error==blot_error::Error.none);
        source.clear();
        let path,error=snapshot.canonical("/tmp/completion-probe.blot");assert(error==blot_error::Error.none);
        let original,error=snapshot.read(path);assert(error==blot_error::Error.none && original=="const value = hel\n");
        let captured,error=blot_reuse_completion_probe::capture(original,17);assert(error==blot_error::Error.none && captured.present);
        var probe=captured.value;assert(probe.prefix=="hel" && probe.replace.start==14 && probe.replace.end==17);
        assert(probe.source=="const value = __blot_editor_probe\n" && probe.originalOffset(probe.marker.end)==17);
        probe.deinit();snapshot.deinit();
    }
    print("completion probe passed: owned snapshot source, prefix, repair, offset and cleanup");
}
