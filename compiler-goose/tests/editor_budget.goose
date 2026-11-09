// Invocation-local engines borrow producer views and the caller's shared editor budget.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.check;
import reuse.project_check;
import reuse.project;
import reuse.completion_fit;
import reuse.revision_inputs;
import reuse.source_overlays;
import support.error;
fn accounting() {
    var budget=blot_reuse_completion_fit::Budget{remaining:10};
    let editor=blot_reuse_project_check::Editor.query{blot_reuse_project_check::EditorQuery{unit:1,marker:blot_check_check::EditorMarker{prefix:"hel",..},budget:budget}};
    blot_reuse_project_check::accountEditorBudget(blot_reuse_project_check::Editor.none,8,true,[]);assert(budget.remaining==10 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,3,false,[]);assert(budget.remaining==7 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,7,false,[]);assert(budget.remaining==0 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,1,false,[]);assert(budget.remaining==0 && budget.exhausted);
    budget=blot_reuse_completion_fit::Budget{remaining:10};blot_reuse_project_check::accountEditorBudget(editor,2,true,[]);assert(budget.remaining==8 && budget.exhausted);
    budget=blot_reuse_completion_fit::Budget{remaining:10};var issues=[default<blot_check_check::Diagnostic>(),default<blot_check_check::Diagnostic>()];
    issues[0].code=blot_check_check::Code.unknown_name;issues[1].code=blot_check_check::Code.inference_budget;
    blot_reuse_project_check::accountEditorBudget(editor,3,false,issues[..1]);assert(budget.remaining==7 && !budget.exhausted);
    blot_reuse_project_check::accountEditorBudget(editor,2,false,issues[..]);assert(budget.remaining==0 && budget.exhausted);
}
fn lifecycle(source:blot_reuse_project::Project&) {
    var prefix:u8[>..]=[];prefix.append("hel");var budget=blot_reuse_completion_fit::Budget{remaining:10};
    var stats=blot_check_check::AliasGlobalStats{..};
    let execution=blot_check_check::PrivateExecution{stats:stats,..};
    let editor=blot_reuse_project_check::Editor.query{blot_reuse_project_check::EditorQuery{unit:source.entry,marker:blot_check_check::EditorMarker{prefix:prefix[..],..},budget:budget}};
    var engine,error=blot_reuse_project_check::initEngine(source,execution,editor,false);assert(error==blot_error::Error.none);
    let context=blot_reuse_project_check::BodyNameContext{engine};let observed .= context.borrow();assert(observed && observed .== engine);
    assert(observed.source.filename(source.entry)=="/tmp/editor-budget.blot" && observed.source.compiled_modules.len==1 && observed.source.compiled_reuse.len==1);
    assert(blot_support::same_slice_identity(observed.source.compiled_modules,source.compiled_modules) && blot_support::same_slice_identity(observed.source.compiled_reuse,source.compiled_reuse));
    assert(engine.execution.stats .== stats);
    match engine.editor {query payload=>{assert(payload.value.marker.prefix=="hel" && blot_support::same_slice_identity(payload.value.marker.prefix,prefix[..]));},none=>{assert(false);}}
    var worker=blot_reuse_project_check::borrowWorker(engine);let worker_context=blot_reuse_project_check::BodyNameContext{worker};assert(worker_context.borrow() .== worker);blot_reuse_project_check::discardWorker(worker);
    blot_reuse_project_check::accountEditorBudget(engine.editor,3,false,[]);assert(budget.remaining==7);engine.deinit();assert(budget.remaining==7 && !budget.exhausted && prefix=="hel");
    var failed,error=blot_reuse_project_check::initEngine(source,execution,editor,false);assert(error==blot_error::Error.none);
    blot_reuse_project_check::accountEditorBudget(failed.editor,2,true,[]);assert(budget.remaining==5 && budget.exhausted);failed.deinit();assert(prefix=="hel");
    // Discarding an unstarted borrowed query does not touch the caller's budget.
    let ignored=editor;assert(budget.remaining==5 && budget.exhausted);
}
fn main() {
    for cycle in 0..3 {
        accounting();let sources=[blot_reuse_source_overlays::Source{path:"/tmp/editor-budget.blot",contents:blot_support::some<const u8[:]>("const value = 1\n")}];
        var snapshot,error=blot_reuse_revision_inputs::initWithSources(blot_reuse_project::Options{..},sources[..]);assert(error==blot_error::Error.none);
        var provider=snapshot.provider();var source,error=blot_reuse_project::loadWithInputs("/tmp/editor-budget.blot",snapshot.options,provider);assert(error==blot_error::Error.none);
        // Nonempty external metadata/mask owners remain local throughout the engine invocation.
        let modules=[default<blot_reuse_frozen_dependency::Module>()];let reuse=[true];source.compiled_modules=modules[..];source.compiled_reuse=reuse[..];
        lifecycle(source);source.deinit();snapshot.deinit();
    }
    print("editor budget passed: lexical engines, producer views, callbacks, borrowed workers, shared budget and cleanup");
}
