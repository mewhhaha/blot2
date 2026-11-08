namespace blot_eval_closed_local_value;
import check.capability_flow;
import reuse.principal_interface;

import check.check_packet_owner;
import check.core;
import check.types;

import check.effects;
import check.check;
import support.option;
type Module=blot_check_core::Module;
type Parameter=blot_check_core::Parameter;
type BindingRef=blot_check_core::BindingRef;
struct Proof { dependencies: BindingRef[16],len: i64=0 }
struct Scan { units: const Module[:],proof: Proof=Proof {..},remaining: i64=512 }
fn unit(self_: Scan&,id: u32) -> const Module? {
 for module,index in self_.units { var actual=module.unit; if actual==0 { actual=(index+1) as u32; } if actual==id { return module; } } return null;
}
fn step(self_: Scan&,depth: i64) -> bool { if depth>=32||self_.remaining==0 { return false; } self_.remaining--; return true; }
fn row(m: const Module&,id: u32,certificates: blot_check_types::List) -> bool {
 let value=m.types.row(id); if value.labels.len!=0 { return false; } match value.tail {
  closed => { return true; },
  variable v => { for item in m.types.list(certificates) { if item==v.value { return true; } } return false; },
  _ => { return false; },
 }
}
fn shape(self_: Scan&,m: const Module&,id: u32,certificates: blot_check_types::List,pure: bool,depth: i64) -> bool {
 if !step(self_,depth) { return false; } let n=m.types.node(id); let tag=n.tag;
 if tag==blot_check_types::Tag.unit||tag==blot_check_types::Tag.boolean||tag==blot_check_types::Tag.unsigned32||tag==blot_check_types::Tag.floating32||tag==blot_check_types::Tag.variable { return true; }
 if tag==blot_check_types::Tag.function {
  if pure&&!row(m,n.c,certificates) { return false; } let input=m.types.node(n.a);
  if input.tag==blot_check_types::Tag.scoped { if input.b!=0||input.c==0||m.types.node(input.c).tag!=blot_check_types::Tag.variable||!shape(self_,m,input.a,certificates,false,depth+1) { return false; } }
  else if !shape(self_,m,n.a,certificates,pure,depth+1) { return false; } return shape(self_,m,n.b,certificates,pure,depth+1);
 }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list { return shape(self_,m,n.a,certificates,pure,depth+1); }
 if tag==blot_check_types::Tag.product { for child in m.types.list(blot_check_types::List {n.a,n.b}) { if !shape(self_,m,child,certificates,pure,depth+1) { return false; } } return true; }
 if tag==blot_check_types::Tag.record { for index in 0..n.b { if !shape(self_,m,m.types.recordField(n,index).ty,certificates,pure,depth+1) { return false; } } return true; }
 if tag==blot_check_types::Tag.nominal { if n.a==0xffffffff { return false; } for child in m.types.nominalArguments(n) { if !shape(self_,m,child,certificates,pure,depth+1) { return false; } } return true; } return false;
}
fn dependency(self_: Scan&,target: BindingRef) -> bool { for prior in self_.proof.dependencies[..self_.proof.len] { if prior.unit==target.unit&&prior.binding==target.binding { return true; } } if self_.proof.len==16 { return false; } self_.proof.dependencies[self_.proof.len]=target; self_.proof.len++; return true; }
fn value(self_: Scan&,owner: u32,id: u32,parameters: const Parameter[:],depth: i64) -> bool {
 if !step(self_,depth)||id==0 { return false; } let module=unit(self_,owner); if module==null { return false; } let m=module; let n=m.node(id); let tag=n.tag;
 if tag!=blot_check_core::Tag.return_||m.types.node(n.ty).tag!=blot_check_types::Tag.never { if !shape(self_,m,n.ty,blot_check_types::List {},false,depth+1) { return false; } }
 if tag==blot_check_core::Tag.constant { return shape(self_,m,n.ty,blot_check_types::List {},true,depth+1); }
 if tag==blot_check_core::Tag.reference {
  let reference=m.reference(id); if reference.unit==0||reference.unit==owner { for parameter in parameters { if parameter.binding!=0&&parameter.binding==reference.binding { return true; } } }
  var target=reference; if target.unit==0 { target.unit=owner; }
  for i in 0..16 {
   let producer=unit(self_,target.unit); if producer==null { return false; } let binding=producer.binding(target.binding);
   if binding.kind==blot_reuse_principal_interface::Kind.external { target=binding.target; continue; }
   let body=producer.body(target.binding); if body==null { return false; }
   if !body.is_function||body.runtime||binding.capability_flow!=blot_check_capability_flow::Contract.input_shape||binding.scheme.generative.len!=0||!binding.capability_parameters.valid() { return false; } return dependency(self_,target);
  }
  return false;
 }
 if tag==blot_check_core::Tag.product||tag==blot_check_core::Tag.record||tag==blot_check_core::Tag.array { for child in m.children(id) { if !value(self_,owner,child,parameters,depth+1) { return false; } } return true; }
 if tag==blot_check_core::Tag.construct { let constructor=m.constructors[n.a]; if m.nominals[constructor.nominal].is_opaque { return false; } if n.b==0 { return true; } return value(self_,owner,n.b,parameters,depth+1); }
 if tag==blot_check_core::Tag.closure { let closure=m.closure(id); if closure.captures.len!=0||closure.qualifier!=0 { return false; } if !shape(self_,m,closure.function_type,closure.closed_rows,true,depth+1) { return false; } return value(self_,owner,closure.body,[closure.parameter],depth+1); }
 if tag==blot_check_core::Tag.return_ { return value(self_,owner,n.a,parameters,depth+1); }
 if tag==blot_check_core::Tag.call {
  var target=m.call(id).target; if target.unit==0 { target.unit=owner; }
  for i in 0..16 {
   let producer=unit(self_,target.unit); if producer==null { return false; } let binding=producer.binding(target.binding);
   if binding.kind==blot_reuse_principal_interface::Kind.external { target=binding.target; continue; }
   let body=producer.body(target.binding); if body==null { return false; } if !body.is_function||body.runtime||body.scheme.obligations.len!=0 { return false; }
   let arguments=m.children(id); if arguments.len!=body.parameters.len { return false; }
   if !shape(self_,producer,binding.ty,body.closed_rows,false,depth+1) { return false; }
   var arrow=binding.ty;
   for index in 0..body.parameters.len { if !step(self_,depth+1) { return false; } let signature=producer.types.node(arrow); if signature.tag!=blot_check_types::Tag.function||!row(producer,signature.c,body.closed_rows) { return false; } arrow=signature.b; }
   for argument in arguments { if !value(self_,owner,argument,parameters,depth+1) { return false; } }
   if !dependency(self_,target) { return false; } return value(self_,target.unit,body.root,producer.bodyParameters(body),depth+1);
  }
  return false;
 }
 return false;
}
fn analyze(units: const Module[:],owner: u32,initializer: u32) -> Proof,bool { var scan=Scan {units:units}; let proven=value(scan,owner,initializer,[],0); return scan.proof,proven; }
fn dataShape(units: const Module[:],owner: u32,ty: u32) -> bool { var scan=Scan {units:units}; let module=unit(scan,owner); if module==null { return false; } return shape(scan,module,ty,blot_check_types::List {},false,0); }
