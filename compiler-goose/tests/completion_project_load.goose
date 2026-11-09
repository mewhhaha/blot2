// The completion provider loads owned snapshot/probe sources through the real Loader.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.completion_probe;
import reuse.editor_completion;
import reuse.revision_inputs;
import reuse.source_overlays;
import reuse.project;
import reuse.partial_dependency;
import reuse.dependency_consumer;
import driver.project_executor;
import support.error;
fn growth() {
    let sources=[
        blot_reuse_source_overlays::Source{path:"/tmp/loader-prelude.blot",contents:blot_support::some<const u8[:]>("infixl 50 (+) = add\ninfixl 50 (-) = add\ninfixl 50 (*) = add\ninfixl 50 (/) = add\ninfixl 50 (<+>) = add\ninfixl 50 (<*>) = add\ninfixl 50 (<$>) = add\ninfixl 50 (<->) = add\ninfixl 50 (<|>) = add\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain0.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain1\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain1.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain2\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain2.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain3\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain3.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain4\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain4.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain5\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain5.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain6\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain6.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain7\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain7.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain8\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain8.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain9\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain9.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain10\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain10.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain11\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain11.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain12\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain12.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain13\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain13.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain14\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain14.blot",contents:blot_support::some<const u8[:]>("import * as next from \"./loader-chain15\"\nconst value = next.value\n")},
        blot_reuse_source_overlays::Source{path:"/tmp/loader-chain15.blot",contents:blot_support::some<const u8[:]>("const value = 1 + 2\n")}
    ];
    let options=blot_reuse_project::Options{prelude_path:blot_support::some<const u8[:]>("/tmp/loader-prelude.blot"),..};
    var snapshot,error=blot_reuse_revision_inputs::initWithSources(options,sources[..]);assert(error==blot_error::Error.none);
    var provider=blot_reuse_editor_completion::Provider{ordinary:snapshot.provider(),filename:"/tmp/loader-chain0.blot"};
    var loaded,error=blot_reuse_project::loadWithInputs("/tmp/loader-chain0.blot",snapshot.options,provider);assert(error==blot_error::Error.none && loaded.diagnostics.items.len==0);
    assert(loaded.units.items.len==17 && loaded.entry==2 && loaded.prelude_unit==1 && loaded.imports.items.len==15);
    assert(loaded.order.items.len==17 && loaded.order.items[0]==1 && loaded.order.items[1]==17 && loaded.order.items[16]==2);
    var done:bool[17]=[false;17];var ready=blot_reuse_project_check::ParallelUnits{};var work=blot_reuse_project_check::ParallelUnits{};
    assert(blot_reuse_project_check::prepareReadyUnits(loaded,done[..],false,ready)==blot_error::Error.none && ready.items==[1 as u32]);
    done[0]=true;assert(blot_reuse_project_check::prepareReadyUnits(loaded,done[..],false,ready)==blot_error::Error.none && ready.items==[17 as u32]);
    for &value in done {value=true;}done[1]=false;
    assert(blot_reuse_project_check::prepareReadyUnits(loaded,done[..],true,ready)==blot_error::Error.none && ready.items.len==0);
    assert(blot_reuse_project_check::prepareReadyUnits(loaded,done[..],false,ready)==blot_error::Error.none && ready.items==[2 as u32]);
    let unsorted=[17 as u32,16 as u32,3 as u32,2 as u32];
    assert(loaded.unit(2).tree.nodes.len==loaded.unit(3).tree.nodes.len && loaded.unit(3).tree.nodes.len==loaded.unit(16).tree.nodes.len && loaded.unit(16).tree.nodes.len<loaded.unit(17).tree.nodes.len);
    assert(blot_reuse_project_check::prepareWorkOrder(loaded,unsorted[..],work)==blot_error::Error.none && work.items==[17 as u32,2 as u32,3 as u32,16 as u32]);
    assert(unsorted==[17 as u32,16 as u32,3 as u32,2 as u32]);
    assert(blot_reuse_project_check::prepareWorkOrder(loaded,loaded.order.items,work)==blot_error::Error.none && work.items.len==17 && work.items[0]==1 && work.items[1]==17 && work.items[16]==16);
    for index in 2..17 {assert(work.items[index]==index as u32);}assert(loaded.order.items[0]==1 && loaded.order.items[16]==2);
    blot_support_pooled_buffer::deinit(work,blot_reuse_project_check::parallel_unit_runs);blot_support_pooled_buffer::deinit(ready,blot_reuse_project_check::parallel_unit_runs);
    snapshot.deinit();assert(loaded.filename(17)=="/tmp/loader-chain15.blot" && loaded.unit(17).source=="const value = 1 + 2\n");loaded.deinit();
}
fn escapedSourceDiagnostics(source:blot_reuse_project::Project&)->blot_reuse_project_check::CheckedProject {
    var engine,error=blot_reuse_project_check::initEngine(source,blot_check_check::PrivateExecution{..},blot_reuse_project_check::Editor.none,true);assert(error==blot_error::Error.none);
    assert(engine.result.allocateModules(source.units.len,true)==blot_error::Error.none && engine.result.allocateReuse(source.units.len)==blot_error::Error.none);
    assert(engine.appendSourceDiagnostics()==blot_error::Error.none);let result=blot_reuse_project_check::finishProject(engine);engine.deinit();return result;
}
fn diagnosticSelection() {
    var bytes:u8[>..]=[];bytes.append("const value = hel\nconst broken =\n");
    let sources=[blot_reuse_source_overlays::Source{path:"/tmp/completion-diagnostic.blot",contents:blot_support::some<const u8[:]>(bytes[..])}];
    var snapshot,error=blot_reuse_revision_inputs::initWithSources(blot_reuse_project::Options{..},sources[..]);assert(error==blot_error::Error.none);bytes.clear();
    let target,error=snapshot.canonical("/tmp/completion-diagnostic.blot");assert(error==blot_error::Error.none);
    let original,error=snapshot.read(target);assert(error==blot_error::Error.none);
    let captured,error=blot_reuse_completion_probe::capture(original,17);assert(error==blot_error::Error.none && captured.present);var probe=captured.value;
    var provider=blot_reuse_editor_completion::Provider{ordinary:snapshot.provider(),filename:target,replacement:blot_support::some<const u8[:]>(probe.source)};
    var loaded,error=blot_reuse_project::loadWithInputs(target,snapshot.options,provider);assert(error==blot_error::Error.none && loaded.diagnostics.items.len!=0);
    var escaped=escapedSourceDiagnostics(loaded);assert(escaped.owner.valid() && escaped.modules.len==loaded.units.len && escaped.body_caches.len==loaded.units.len && escaped.diagnostics.len==loaded.diagnostics.len);
    assert(escaped.reused_modules.len==loaded.units.len && escaped.interface_colors.len==loaded.units.len && escaped.binding_maps.len==loaded.units.len && escaped.relocated_modules.len==loaded.units.len);
    assert(!escaped.modules[0].present && !escaped.reused_modules[0] && !escaped.binding_maps[0].present && !escaped.relocated_modules[0].present && escaped.diagnostics[0].source.value.message().len!=0);
    let escaped_owner=escaped.owner;escaped.deinit();assert(!escaped_owner.valid());
    let issue=loaded.diagnostics.items[0];let expected=probe.originalSpan(issue.span);var truncated=false;
    var selected,error=blot_reuse_editor_completion::loadedDiagnostic(loaded,target,issue,probe,loaded.entry,truncated);assert(error==blot_error::Error.none && selected.start==expected.start && selected.end==expected.end);
    var global_issue=issue;global_issue.unit=0;
    var fallback,error=blot_reuse_editor_completion::loadedDiagnostic(loaded,target,global_issue,probe,loaded.entry,truncated);assert(error==blot_error::Error.none && fallback.start==issue.span.start && fallback.end==issue.span.end);
    var diagnostics=blot_support_pooled_buffer::Buffer<blot_reuse_editor_completion::Diagnostic>{};
    assert(blot_support_pooled_buffer::push(diagnostics,selected,blot_reuse_editor_completion::diagnostic_pool)==blot_error::Error.none);
    assert(blot_support_pooled_buffer::push(diagnostics,fallback,blot_reuse_editor_completion::diagnostic_pool)==blot_error::Error.none);
    var result=blot_reuse_editor_completion::Result{};assert(blot_reuse_editor_completion::publishDiagnostics(result,diagnostics,target)==blot_error::Error.none);
    blot_support_pooled_buffer::deinit(diagnostics,blot_reuse_editor_completion::diagnostic_pool);
    var engine,error=blot_reuse_project_check::initEngine(loaded,blot_check_check::PrivateExecution{..},blot_reuse_project_check::Editor.none,false);assert(error==blot_error::Error.none);
    assert(engine.appendSourceDiagnostics()==blot_error::Error.none && engine.diagnostics.items.len==loaded.diagnostics.len);
    let source_count=engine.diagnostics.items.len;
    var detail:u8[>..]=[];detail.append("semantic detail");var operation:u8[>..]=[];operation.append("Effect.perform");
    var holes=blot_reuse_hole_diagnostics::Builder{};let hole_id,error=holes.addNode(blot_reuse_hole_diagnostics::Node{name:blot_support::some<const u8[:]>(blot_reuse_hole_diagnostics::copyText("HoleType"))});assert(error==blot_error::Error.none);
    var hole=holes.finish(hole_id,blot_reuse_hole_diagnostics::Span{});holes.deinit();
    var explanation_builder=blot_reuse_dispatch_explanation::Builder{};
    let operand,error=explanation_builder.ownText("operand");assert(error==blot_error::Error.none);
    let origin,error=explanation_builder.makeOrigin("origin",blot_support::some<const u8[:]>("origin.blot"),blot_support::none<blot_parse_ast::Span>());assert(error==blot_error::Error.none);
    explanation_builder.addOrigin(blot_support::some<const u8[:]>(operand),blot_reuse_dispatch_explanation::Outcome.selected,origin);
    var explanation,error=explanation_builder.finish(blot_support::some<const u8[:]>("dispatch"),blot_support::none<const u8[:]>());assert(error==blot_error::Error.none);explanation_builder.deinit();
    let witness=blot_check_check::PurityWitness{identity:blot_check_types::NominalIdentity{7,9},operation_name:blot_support::some<const u8[:]>(operation[..]),..};
    let semantic=[blot_check_check::Diagnostic{origin_unit:loaded.entry,code:blot_check_check::Code.unknown_name,span:issue.span,node:0,purity:blot_support::some(witness),detail:blot_support::some<const u8[:]>(detail[..]),hole:blot_support::some(hole),explanation:blot_support::some(explanation),..}];
    assert(engine.appendDiagnostics(loaded.entry,semantic[..])==blot_error::Error.none && engine.diagnostics.items.len==source_count+1);
    hole.deinit();explanation.deinit();detail.clear();operation.clear();
    var job=blot_reuse_project_check::ParallelJob{};job.diagnostics=blot_reuse_project_check::owned_Diagnostic.alloc_slice(engine.diagnostics.items.len);
    for &diagnostic in job.diagnostics {diagnostic=default<blot_reuse_project_check::Diagnostic>();}
    for index in 0..job.diagnostics.len {let copied,error=blot_project_executor::cloneDiagnostic(engine,engine.diagnostics.items[index]);assert(error==blot_error::Error.none);job.diagnostics[index]=copied;}
    let checked=blot_reuse_project_check::finishProject(engine);engine.deinit();
    assert(checked.diagnostics.len==job.diagnostics.len && checked.diagnostics[0].source.present && job.diagnostics[0].source.present);
    assert(checked.diagnostics[0].source.value.code==issue.code && job.diagnostics[0].source.value.lexical_details==issue.lexical_details);
    assert(blot_support::same_slice_identity(checked.diagnostics[0].source.value.publication.value.message,job.diagnostics[0].source.value.publication.value.message));
    let rich=checked.diagnostics[source_count];let cloned=job.diagnostics[source_count];
    assert(rich.detail.value=="semantic detail" && cloned.detail.value=="semantic detail" && !blot_support::same_slice_identity(rich.detail.value,cloned.detail.value));
    assert(rich.purity.value.operation_name.value=="Effect.perform" && cloned.purity.value.identity==blot_check_types::NominalIdentity{7,9});
    assert(rich.hole.value.nodes[0].name.value=="HoleType" && cloned.hole.value.nodes[0].name.value=="HoleType");
    assert(rich.explanation.value.operation.value=="dispatch" && cloned.explanation.value.candidates[0].origin.value.path.value=="origin.blot");
    var owned_checked=checked;owned_checked.deinit();job.deinit();
    let consumer,error=blot_reuse_dependency_consumer::init(loaded.entry,"check-project","rejected",issue.span,"rejection message");assert(error==blot_error::Error.none);
    var rejection,error=blot_reuse_partial_dependency::reject(loaded,"/tmp/fallback-request.blot",consumer);assert(error==blot_error::Error.none);
    assert(blot_reuse_partial_dependency::diagnosticFilename(loaded,"/tmp/fallback-request.blot",0)=="/tmp/fallback-request.blot");
    let empty=blot_reuse_partial_dependency::Result{};assert(blot_reuse_partial_dependency::diagnosticFilename(empty,"/tmp/fallback-request.blot")=="/tmp/fallback-request.blot");
    loaded.deinit();probe.deinit();snapshot.deinit();
    match rejection {rejected payload=>{
        let filename=blot_reuse_partial_dependency::diagnosticFilename(payload.value,"/tmp/fallback-request.blot");assert(filename=="/tmp/completion-diagnostic.blot");
        var formatted:u8[>..]=[];assert(payload.value.result.diagnostic.value.write(formatted,filename)==blot_error::Error.none && formatted.len!=0);
        assert(payload.value.result.diagnostic.value.code=="rejected" && payload.value.result.diagnostic.value.message=="rejection message");
    },_=>{abort("missing rejection");}}rejection.deinit();
    assert(result.diagnostics.len==2 && result.diagnostics[0].filename=="/tmp/completion-diagnostic.blot" && result.diagnostics[0].code.len!=0 && result.diagnostics[0].message.len!=0);
    assert(result.diagnostics[1].filename=="/tmp/completion-diagnostic.blot" && result.diagnostics[1].code==result.diagnostics[0].code && result.diagnostics[1].message==result.diagnostics[0].message);
    result.deinit();
}
fn diagnosticLimits() {
    for mode in 0..2 {
        var diagnostics=blot_support_pooled_buffer::Buffer<blot_reuse_editor_completion::Diagnostic>{};var truncated=false;
        for index in 0..16 {let issue,error=blot_reuse_editor_completion::diagnostic("/tmp/limits.blot","synthetic","message",blot_parse_ast::Span{index as u32,(index+1) as u32},truncated);assert(error==blot_error::Error.none);assert(blot_support_pooled_buffer::push(diagnostics,issue,blot_reuse_editor_completion::diagnostic_pool)==blot_error::Error.none);}
        var result=blot_reuse_editor_completion::Result{};if mode==0 {result.truncated=true;}
        assert(blot_reuse_editor_completion::publishDiagnostics(result,diagnostics,"/tmp/limits.blot")==blot_error::Error.none);
        blot_support_pooled_buffer::deinit(diagnostics,blot_reuse_editor_completion::diagnostic_pool);
        if mode==1 {assert(result.noteLimit("/tmp/limits.blot")==blot_error::Error.none);}
        assert(result.truncated && result.diagnostics.len==16 && result.diagnostics[0].code=="completion_limit" && result.diagnostics[1].start==0 && result.diagnostics[15].start==14);
        assert(result.noteLimit("/tmp/limits.blot")==blot_error::Error.none && result.diagnostics.len==16);result.deinit();
    }
}
fn itemPublication() {
    var items=blot_support_pooled_buffer::Buffer<blot_reuse_editor_completion::Item>{};
    for index in 0..130 {
        let item=blot_reuse_editor_completion::Item{label:blot_reuse_editor_completion::own("item"),insertText:blot_reuse_editor_completion::own("item"),detail:blot_support::some<const u8[:]>(blot_reuse_editor_completion::own("detail")),distance:(129-index) as u32,filename:blot_reuse_editor_completion::own("/tmp/item.blot")};
        assert(blot_support_pooled_buffer::push(items,item,blot_reuse_editor_completion::item_pool)==blot_error::Error.none);
    }
    var removed=blot_reuse_editor_completion::itemRun(items.storage)[0];blot_reuse_editor_completion::shiftItems(items,0);blot_support_pooled_buffer::resize(items,129);removed.deinit();
    var result=blot_reuse_editor_completion::Result{};blot_reuse_editor_completion::publishItems(result,items);
    assert(items.items.len==0 && result.truncated && result.items.len==128 && result.items[0].distance==0 && result.items[127].distance==127);
    blot_support_pooled_buffer::deinit(items,blot_reuse_editor_completion::item_pool);
    assert(result.items[0].filename=="/tmp/item.blot" && result.items[0].detail.present && result.items[0].detail.value=="detail");result.deinit();
}
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
        var provider=blot_reuse_editor_completion::Provider{ordinary:snapshot.provider(),filename:path,replacement:blot_support::some<const u8[:]>(probe.source)};
        var loaded,error=blot_reuse_project::loadWithInputs(path,snapshot.options,provider);assert(error==blot_error::Error.none && loaded.diagnostics.items.len==0);
        assert(loaded.units.items.len==1 && loaded.entry==1 && loaded.filename(1)=="/tmp/completion-probe.blot" && loaded.unit(1).source==probe.source);
        loaded.deinit();probe.deinit();snapshot.deinit();
    }
    growth();diagnosticSelection();diagnosticLimits();itemPublication();
    print("completion project loader passed: owned snapshot, replacement, map/stack/fixity growth, import order, diagnostic limits, item moves, parallel ready/work order and cleanup");
}
