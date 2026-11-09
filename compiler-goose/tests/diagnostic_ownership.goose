import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import support.option;
import support.error;
import check.types;
import parse.ast;
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
    let error=builder.scope.push(blot_reuse_hole_diagnostics::canonicalBinding(Binding{name:binding_name,ty:id,requirements:span}),blot_reuse_hole_diagnostics::binding_pool);
    assert(error==blot_error::Error.none);
    let error=builder.requirements.push(blot_reuse_hole_diagnostics::canonicalRequirement(Requirement{kind:blot_check_types::ObligationKind.field,name:name(mode),subject:id}),blot_reuse_hole_diagnostics::requirement_pool);
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
    assert(copied.operation.value=="+" && copied.candidates[0].origin.value.name.value=="name");
    assert(copied.candidates[0].origin.value.path.value=="path" && copied.candidates[0].operand.value=="operand");
    assert(copied.steps[0].member.value=="member" && copied.steps[0].ty.present && copied.steps[0].ty.value.len==0);
    copied.deinit();builder.deinit();
}
fn main() {for cycle in 0..3 {for mode in 0..3 {holes(mode);}dispatch();}print("diagnostic ownership passed: canonical names, move, clone and cleanup");}
