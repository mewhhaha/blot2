// Native regression for declaration scheme cycles, order, reset and admission.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.declaration_dependencies;
import check.core;
import check.types;
import support.error;
type Core=blot_check_core::Module;
type Obligation=blot_check_core::Obligation;
type Scheme=blot_check_types::Scheme;
type Member=blot_check_core::DependencyMember;
fn callee(binding:u32,unit:u32=0)->Obligation {return Obligation {kind:blot_check_types::ObligationKind.callee_use,identity:blot_check_types::NominalIdentity {unit,binding,..},..};}
fn member(name:u32,explicit_:bool=true)->Obligation {return Obligation {kind:blot_check_types::ObligationKind.dispatch,name:name,explicit:explicit_,..};}
fn scheme(start:u32,len:u32)->Scheme {return Scheme {obligations:blot_check_types::List {start,len,..},..};}
fn selected(module:const Core&,body:blot_check_core::Body) {
 var output:Member[>..<]=[];
 assert(blot_reuse_declaration_dependencies::selectionMembers(module,body,output)==blot_error::Error.none);
 assert(output.len==4 && output[0].name==11 && output[1].name==22 && output[2].name==33 && output[3].name==99);
}
fn captured(module:const Core&) {
 var declarations:blot_check_core::DeclarationDependencies[>..<]=[];
 var references:blot_check_core::BindingRef[>..<]=[];
 var members:Member[>..<]=[];
 assert(blot_reuse_declaration_dependencies::capture(module,declarations,references,members)==blot_error::Error.none);
 assert(declarations.len==3 && references.len==0 && members.len==6);
 for offset in 0..2 {let recipe=declarations[offset+1];assert(recipe.members.start==offset*3 && recipe.members.len==3);for index in 0..3 {assert(members[offset*3+index].name==(index+1)*11);}}
}
fn rejected(module:const Core&,body:blot_check_core::Body) {
 var selected:Member[>..<]=[];
 assert(blot_reuse_declaration_dependencies::selectionMembers(module,body,selected)==blot_error::Error.core_limit && selected.len==0);
 var declarations:blot_check_core::DeclarationDependencies[>..<]=[];
 var references:blot_check_core::BindingRef[>..<]=[];
 var members:Member[>..<]=[];
 assert(blot_reuse_declaration_dependencies::capture(module,declarations,references,members)==blot_error::Error.core_limit);
 assert(declarations.len==0 && references.len==0 && members.len==0);
}
fn epochWrap(module:const Core&,body:blot_check_core::Body) {
 var work:blot_reuse_declaration_dependencies::Work[>..]=[];
 var references:blot_check_core::BindingRef[>..]=[];
 var locations:u32[>..]=[];
 var members:Member[>..]=[];
 assert(module.bindings.len==66);var marks:u32[66]=default<u32[66]>();for &mark in marks {mark=1;}
 var scan=blot_reuse_declaration_dependencies::Capture {module:module,work:work,references:references,locations:locations,members:members,schemes_seen:marks[..],seen_epoch:0xffffffff,..};
 let first,error=scan.scan(body);assert(error==blot_error::Error.none && scan.seen_epoch==1 && first.members.start==0 && first.members.len==3);
 assert(marks[0]==0 && marks[62]==0 && marks[63]==1 && marks[64]==1 && marks[65]==1);
 let second,error=scan.scan(body);assert(error==blot_error::Error.none && scan.seen_epoch==2 && second.members.start==3 && second.members.len==3);
 assert(marks[0]==0 && marks[63]==2 && marks[64]==2 && marks[65]==2);
 for index in 0..6 {assert(members[index].name==(index%3+1)*11);}
 let third,error=scan.scan(blot_check_core::Body {root:3,..});assert(error==blot_error::Error.none && scan.work_top==0 && work.len==2 && third.references.start==0 && third.references.len==2);
 assert(references[0].binding==17 && references[1].binding==18 && locations[0]==1 && locations[1]==2);
 let fourth,error=scan.scan(blot_check_core::Body {root:3,..});assert(error==blot_error::Error.none && scan.work_top==0 && work.len==2 && fourth.references.start==2 && fourth.references.len==2);
 assert(references[2].binding==17 && references[3].binding==18 && locations[2]==1 && locations[3]==2);
}
fn nodeCapture(module:Core) {
 var bodies:blot_check_core::Body[3]=[blot_check_core::Body {..},blot_check_core::Body {root:3,..},blot_check_core::Body {root:3,..}];
 var local=module;local.bodies=bodies[..];
 var declarations:blot_check_core::DeclarationDependencies[>..<]=[];var references:blot_check_core::BindingRef[>..<]=[];var members:Member[>..<]=[];
 assert(blot_reuse_declaration_dependencies::capture(local,declarations,references,members)==blot_error::Error.none);
 assert(references.len==4 && declarations[1].references.start==0 && declarations[2].references.start==2);
 for index in 0..4 {assert(references[index].binding==17+index%2);}
 declarations.clear();references.clear();members.clear();bodies[2].root=4;
 assert(blot_reuse_declaration_dependencies::capture(local,declarations,references,members)==blot_error::Error.core_limit);
 assert(declarations.len==0 && references.len==0 && members.len==0);
}
fn main() {
 var bindings:blot_check_core::Binding[66]=default<blot_check_core::Binding[66]>();
 bindings[63].scheme=scheme(5,2);bindings[64].scheme=scheme(7,2);bindings[65].scheme=scheme(9,2);
 var obligations:Obligation[11]=[callee(63),callee(64,7),callee(65),callee(63),member(99,false),member(11),callee(64),member(22),callee(65),member(33),callee(63)];
 let body=blot_check_core::Body {scheme:scheme(0,5),..};
 var bodies:blot_check_core::Body[3]=[default<blot_check_core::Body>(),body,body];
 var nodes:blot_check_core::Node[4]=default<blot_check_core::Node[4]>();nodes[1]=blot_check_core::Node {tag:blot_check_core::Tag.reference,a:0,..};nodes[2]=blot_check_core::Node {tag:blot_check_core::Tag.reference,a:1,..};nodes[3]=blot_check_core::Node {tag:blot_check_core::Tag.product,a:0,b:2,..};
 var extra:u32[2]=[1 as u32,2 as u32];var node_refs:blot_check_core::BindingRef[2]=[blot_check_core::BindingRef {9,17,..},blot_check_core::BindingRef {9,18,..}];
 var module=default<Core>();module.unit=7;module.nodes=nodes[..];module.extra=extra[..];module.references=node_refs[..];module.bindings=bindings[..];module.obligations=obligations[..];module.bodies=bodies[..];
 selected(module,body);captured(module);selected(module,body);epochWrap(module,body);nodeCapture(module);
 // Reject zero, exact upper bound, far OOB and a foreign-unit callee before indexing.
 for invalid in [0 as u32,66 as u32,0xffffffff as u32] {obligations[0]=callee(invalid);rejected(module,body);}
 obligations[0]=callee(63,8);rejected(module,body);
 obligations[0]=callee(63);selected(module,body);captured(module);
 print("declaration scheme cycles passed: 63/64/65, duplicates, order, reset, selection and admission");
}
