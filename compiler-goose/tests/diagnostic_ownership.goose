import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.hole_diagnostics;
import eval.core_eval;
import reuse.dispatch_explanation;
import driver.compile_workspace;
import support.native;
import support.option;
import support.error;
import check.types;
import parse.ast;
import backend.storage_diagnostic;
type Text=blot_reuse_hole_diagnostics::Text;
type Node=blot_reuse_hole_diagnostics::Node;
type Edge=blot_reuse_hole_diagnostics::Edge;
type Binding=blot_reuse_hole_diagnostics::Binding;
type Requirement=blot_reuse_hole_diagnostics::Requirement;
fn name(mode:i64)->Text {
    if mode==0 {return blot_support::none<const u8[:]>();}
    if mode==1 {return blot_support::some(blot_reuse_hole_diagnostics::copyText(""));}
    return blot_support::some(blot_reuse_hole_diagnostics::copyText("owned"));
}
fn checkName(value:Text,mode:i64) {
    assert(value.present==(mode!=0));
    if value.present {if mode==1 {assert(value.value.len==0);}else {assert(value.value=="owned");}}
}
fn holes(mode:i64) {
    var builder=blot_reuse_hole_diagnostics::Builder{};
    let id,error=builder.addNode(Node{name:name(mode)});
    assert(error==blot_error::Error.none && id==0);
    let children=[Edge{name:name(mode),ty:id}];
    let span,error=builder.save(children);
    assert(error==blot_error::Error.none && span.start==0 && span.len==1);
    var binding_name=blot_reuse_hole_diagnostics::copyText("");
    if mode==2 {binding_name=blot_reuse_hole_diagnostics::copyText("owned");}
    let error=blot_reuse_hole_diagnostics::pushOwned(builder.scope,blot_reuse_hole_diagnostics::canonicalBinding(Binding{name:binding_name,ty:id,requirements:span}));
    assert(error==blot_error::Error.none);
    let error=blot_reuse_hole_diagnostics::pushOwned(builder.requirements,blot_reuse_hole_diagnostics::canonicalRequirement(Requirement{kind:blot_check_types::ObligationKind.field,name:name(mode),subject:id}));
    assert(error==blot_error::Error.none);
    var original=builder.finish(id,span);
    assert(!builder.nodes.items[0].name.present && !builder.edges.items[0].name.present);
    assert(builder.scope.items[0].name.len==0 && !builder.requirements.items[0].name.present);
    builder.deinit();
    var moved=blot_reuse_hole_diagnostics::canonicalOwned(original);
    original=blot_reuse_hole_diagnostics::Snapshot{};
    var copied,error=moved.clone();assert(error==blot_error::Error.none);
    checkName(moved.nodes[0].name,mode);checkName(moved.edges[0].name,mode);checkName(moved.requirements[0].name,mode);
    if mode==2 {assert(moved.scope[0].name=="owned");assert(!blot_support::same_slice_identity(moved.nodes[0].name.value,copied.nodes[0].name.value));}else {assert(moved.scope[0].name.len==0);}
    moved.deinit();original.deinit();
    checkName(copied.nodes[0].name,mode);checkName(copied.edges[0].name,mode);checkName(copied.requirements[0].name,mode);
    copied.deinit();assert(copied.nodes.len==0 && copied.edges.len==0 && copied.scope.len==0 && copied.requirements.len==0);
}
fn dispatch() {
    var builder=blot_reuse_dispatch_explanation::Builder{};
    let operand,error=builder.ownText("operand");assert(error==blot_error::Error.none);
    let origin,error=builder.makeOrigin("name",blot_support::some<const u8[:]>("path"),blot_support::none<blot_parse_ast::Span>());assert(error==blot_error::Error.none);
    builder.addOrigin(blot_support::some(operand),blot_reuse_dispatch_explanation::Outcome.selected,origin);
    let ty,error=builder.ownText("");assert(error==blot_error::Error.none);
    let error=builder.addStep(blot_support::some<const u8[:]>("member"),blot_support::some(ty),blot_reuse_dispatch_explanation::Outcome.selected);assert(error==blot_error::Error.none);
    var original,error=builder.finish(blot_support::some<const u8[:]>("+"),blot_support::none<const u8[:]>());assert(error==blot_error::Error.none);
    var moved=blot_reuse_dispatch_explanation::canonicalOwned(original);original=blot_reuse_dispatch_explanation::Explanation{operation:blot_support::none<const u8[:]>(),member:blot_support::none<const u8[:]>()};
    var copied,error=moved.clone();assert(error==blot_error::Error.none);moved.deinit();original.deinit();
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());
    assert(frame.release()==blot_error::Error.none);
    assert(copied.operation.value=="+" && copied.candidates[0].origin.value.name.value=="name");
    assert(copied.candidates[0].origin.value.path.value=="path" && copied.candidates[0].operand.value=="operand");
    assert(copied.steps[0].member.value=="member" && copied.steps[0].ty.present && copied.steps[0].ty.value.len==0);
    copied.deinit();builder.deinit();
}
fn sessionDiagnostic() {
 let allocated,error=blot_eval_core_eval::initOwnedEmptySession(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && allocated);let session:blot_eval_core_eval::Session& =allocated;
 assert(blot_eval_core_eval::registeredDiagnosticMessage(session.owned_diagnostic_message).len==0);
 {var source:u8[>..]=[];source.append("owned session diagnostic");session.owned_diagnostic_message.append(source[..]);}
 session.diagnostic=blot_support::Option<blot_eval_core_eval::Diagnostic>{true,blot_eval_core_eval::Diagnostic{unit:1,span:blot_parse_ast::Span{0,1},code:blot_check_diagnostic_code::Code.missing_field,detail:blot_eval_core_eval::registeredDiagnosticMessage(session.owned_diagnostic_message)}};
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);assert(session.diagnostic.value.detail=="owned session diagnostic");
 let capacity=session.owned_diagnostic_message.storage.len;session.discardDiagnostic();assert(!session.diagnostic.present && session.owned_diagnostic_message.storage.len==capacity && blot_eval_core_eval::registeredDiagnosticMessage(session.owned_diagnostic_message).len==0);
 session.owned_diagnostic_message.append("again");assert(blot_eval_core_eval::registeredDiagnosticMessage(session.owned_diagnostic_message)=="again");blot_eval_core_eval::deinitOwnedSession(session);
}
fn panicMessageOwnership() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);let names,error=owner.copy("owned panic");assert(error==blot_error::Error.none);
 let nodes,error=owner.copy([blot_check_core::Node{tag:blot_check_core::Tag.invalid,..},blot_check_core::Node{tag:blot_check_core::Tag.panic,a:0,b:11,..},blot_check_core::Node{tag:blot_check_core::Tag.panic,a:0,b:0,..}]);assert(error==blot_error::Error.none);let spans,error=owner.copy([blot_parse_ast::Span{0,0},blot_parse_ast::Span{7,19},blot_parse_ast::Span{21,22}]);assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(owner,1);assert(error==blot_error::Error.none);units[0]=blot_check_core::Module{unit:1,nodes:nodes,spans:spans,names:names,..};
 let allocated,error=blot_eval_core_eval::initOwnedSession(units,blot_native::fresh_owner_id());assert(error==blot_error::Error.none && allocated);let session:blot_eval_core_eval::Session& =allocated;
 assert(blot_eval_core_eval::panicDiagnostic(session,0,1)==blot_error::Error.declined && session.diagnostic.present && session.diagnostic.value.unit==1 && session.diagnostic.value.span==blot_parse_ast::Span{7,19} && session.diagnostic.value.code==blot_check_diagnostic_code::Code.const_panic && session.diagnostic.value.detail=="owned panic");
 assert(blot_eval_core_eval::panicDiagnostic(session,0,2)==blot_error::Error.declined && session.diagnostic.value.detail=="owned panic" && session.diagnostic.value.span==blot_parse_ast::Span{7,19});
 session.discardDiagnostic();assert(blot_eval_core_eval::panicDiagnostic(session,0,2)==blot_error::Error.declined && session.diagnostic.value.detail.len==0 && session.diagnostic.value.span==blot_parse_ast::Span{21,22});session.discardDiagnostic();assert(blot_eval_core_eval::panicDiagnostic(session,0,1)==blot_error::Error.declined);
 // End the unit borrow before retiring the producer; diagnostic text is independent.
 session.units=default<const blot_check_core::Module[:]>();owner.deinit();var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);assert(session.diagnostic.value.detail=="owned panic" && session.diagnostic.value.span==blot_parse_ast::Span{7,19});blot_eval_core_eval::deinitOwnedSession(session);
}
fn diagnosticRestoration() {
 let allocated,error=blot_eval_core_eval::initOwnedEmptySession(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && allocated);let session:blot_eval_core_eval::Session& =allocated;
 var trace=blot_check_staging_origins::Trace{};trace.len=1;let dispatch=blot_eval_core_eval::DispatchRecord{member:17,..};let implementation=blot_eval_implementation_trace::Record{request:23,..};
 session.diagnostic=blot_support::Option<blot_eval_core_eval::Diagnostic>{true,blot_eval_core_eval::Diagnostic{unit:4,span:blot_parse_ast::Span{7,19},code:blot_check_diagnostic_code::Code.unsupported,detail:"static prior detail",tag_origin:true,related:blot_support::Option<blot_eval_core_eval::SourceLocation>{true,blot_eval_core_eval::SourceLocation{2,blot_parse_ast::Span{1,3}}},origins:trace,dispatch:blot_support::Option<blot_eval_core_eval::DispatchRecord>{true,dispatch},implementation_trace:blot_support::Option<blot_eval_implementation_trace::Record>{true,implementation}}};
 let steps=session.steps;assert(!blot_eval_core_eval::diagnosticProbeAllowed(session) && session.steps==steps && session.diagnostic.value.detail=="static prior detail");
 let metadata=blot_eval_core_eval::diagnosticMetadata(session.diagnostic);assert(metadata.value.detail.len==0);var message=blot_eval_core_eval::CoreBytesBuffer{};message.append(session.diagnostic.value.detail);assert(message.failure==blot_error::Error.none);
 session.discardDiagnostic();assert(blot_eval_core_eval::diagnosticProbeAllowed(session));session.owned_diagnostic_message.append("temporary failure");assert(blot_eval_core_eval::restoreDiagnostic(session,metadata,message.items)==blot_error::Error.none);
 let actual=session.diagnostic.value;assert(actual.unit==4 && actual.span==blot_parse_ast::Span{7,19} && actual.code==blot_check_diagnostic_code::Code.unsupported && actual.detail=="static prior detail" && actual.tag_origin && actual.related.value.unit==2 && actual.origins.len==1 && actual.dispatch.value.member==17 && actual.implementation_trace.value.request==23);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);assert(session.diagnostic.value.detail=="static prior detail");let length=session.owned_diagnostic_message.len;let replacement=blot_support::Option<blot_eval_core_eval::Diagnostic>{true,blot_eval_core_eval::Diagnostic{unit:77,span:blot_parse_ast::Span{100,200},code:blot_check_diagnostic_code::Code.const_panic}};session.owned_diagnostic_message.failure=blot_error::Error.out_of_memory;assert(blot_eval_core_eval::restoreDiagnostic(session,replacement,"replacement") == blot_error::Error.out_of_memory);assert(session.diagnostic.value.unit==4 && session.diagnostic.value.span==blot_parse_ast::Span{7,19} && session.diagnostic.value.detail=="static prior detail" && session.owned_diagnostic_message.len==length && session.owned_diagnostic_message.failure==blot_error::Error.out_of_memory && blot_eval_core_eval::registeredDiagnosticMessage(session.owned_diagnostic_message)=="static prior detail");session.owned_diagnostic_message.failure=blot_error::Error.none;message.deinit();session.discardDiagnostic();assert(blot_eval_core_eval::diagnosticProbeAllowed(session) && session.owned_diagnostic_message.len==0);assert(blot_eval_core_eval::restoreDiagnostic(session,blot_support::none<blot_eval_core_eval::Diagnostic>(),default<const u8[:]>())==blot_error::Error.none && !session.diagnostic.present);blot_eval_core_eval::deinitOwnedSession(session);
}
fn scopedDiagnostic(text:const u8[:])->blot_backend_storage_diagnostic::Diagnostic {
 var producer:u8[>..]=[];producer.append(text);
 let value=blot_backend_storage_diagnostic::Diagnostic{unit:7,span:blot_check_core::Span{11,19},code:blot_check_diagnostic_code::Code.storage_unsupported,detail:blot_backend_storage_diagnostic::detailId(producer[..])};
 producer.clear();producer.append("retired");return value;
}
fn scopedDiagnostics() {
 for index in 0..blot_backend_storage_diagnostic::detail_count {
  let value=scopedDiagnostic(blot_backend_storage_diagnostic::detailText(blot_backend_storage_diagnostic::Diagnostic{detail:index as u32,..}));
  var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
  assert(value.unit==7 && value.span.start==11 && value.span.end==19 && value.code==blot_check_diagnostic_code::Code.storage_unsupported && value.detail==index);
  assert(blot_backend_storage_diagnostic::detailId(blot_backend_storage_diagnostic::detailText(value))==index);
 }
}
fn main() {scopedDiagnostics();diagnosticRestoration();panicMessageOwnership();sessionDiagnostic();for cycle in 0..3 {for mode in 0..3 {holes(mode);}dispatch();}print("diagnostic ownership passed: canonical names, move, clone and cleanup");}
