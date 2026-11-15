// Principal payloads remain untrusted until bounds, graph and contract admission.
namespace blot_reuse_dependency_interface_validation;
import std;
import dictionary;
import reuse.principal_interface;
import check.types;
import check.effects;
import check.frozen_types;
import check.parameter_patterns;
import check.quantifier_goals;
import check.capability_flow;
import check.numeric_proof_terms;
import check.numeric_proof_core;
import check.associated_admission;
import check.rank_portable;
import eval.implementation_admission;
import backend.opaque_storage;
import support.error;
import support.option;
type Error=blot_error::Error;
type Interface=blot_reuse_principal_interface::Interface;
type Tag=blot_check_types::Tag;
type List=blot_check_types::List;
fn require(value:bool)->Error {if !value {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}
fn range(start:u32,count:u32,length:i64)->Error {return require(start<=length&&count<=length-start);}
fn ty(owner:const Interface&,id:u32)->Error {return require(id<owner.graph.nodes.len);}
fn units(id:u32,count:i64)->Error {return require(id==0||id==0xffffffff||id<=count);}
fn identity(value:blot_check_types::NominalIdentity,symbol_count:i64,unit_count:i64)->Error {
 { let propagated_error = units(value.unit,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
 if value.unit!=0&&value.unit!=0xffffffff&&value.decl&blot_check_types::opaque_name_bit!=0 {{ let propagated_error = require((value.decl&~blot_check_types::opaque_name_bit)<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 return blot_error::Error.none;
}
fn target(owner:const Interface&,value:blot_reuse_principal_interface::ExternalTarget,unit_count:i64)->Error {{ let propagated_error = units(value.unit,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }if value.unit==0||value.unit==owner.unit {{ let propagated_error = require(value.binding<owner.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn callee(owner:const Interface&,value:blot_check_types::Obligation,local:bool,unit_count:i64)->Error {
 if value.kind!=blot_check_types::ObligationKind.callee_use {return blot_error::Error.none;}
 if local||value.identity.unit==0||value.identity.unit==owner.unit {return require(value.identity.decl!=0&&value.identity.decl<owner.bindings.len);}
 { let propagated_error = require(value.identity.unit<=unit_count&&value.identity.decl!=0); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for binding in owner.bindings {if binding.kind!=blot_reuse_principal_interface::Kind.external||!binding.external.present {continue;}let external=binding.external.value;if external.unit==value.identity.unit&&external.binding==value.identity.decl {return blot_error::Error.none;}}
 return blot_error::Error.invalid_artifact;
}
fn typeList(owner:const Interface&,value:List)->Error {{ let propagated_error = range(value.start,value.len,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }for id in owner.graph.extra[value.start..value.start+value.len] {{ let propagated_error = ty(owner,id); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn variableList(owner:const Interface&,value:List)->Error {{ let propagated_error = range(value.start,value.len,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }for id in owner.graph.extra[value.start..value.start+value.len] {{ let propagated_error = ty(owner,id); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(owner.graph.nodes[id].tag==blot_check_types::Tag.variable); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn namesList(owner:const Interface&,value:List,count:i64)->Error {{ let propagated_error = range(value.start,value.len,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }for id in owner.graph.extra[value.start..value.start+value.len] {{ let propagated_error = require(id<count); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn patternList(owner:const Interface&,value:List)->Error {{ let propagated_error = range(value.start,value.len,owner.patterns.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }for id in owner.patterns.extra[value.start..value.start+value.len] {{ let propagated_error = require(id<owner.patterns.nodes.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;}
fn scheme(owner:const Interface&,value:blot_check_types::Scheme)->Error {
 { let propagated_error = ty(owner,value.root); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = variableList(owner,value.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,value.row_variables,owner.graph.row_variable_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,value.closed_rows,owner.graph.row_variable_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
 { let propagated_error = range(value.obligations.start,value.obligations.len,owner.obligations.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(value.generative.len<=32&&value.generative.len%2==0); if propagated_error != blot_error::Error.none { return propagated_error; } }
 { let propagated_error = range(value.generative.start,value.generative.len,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }let binders=owner.graph.extra[value.generative.start..value.generative.start+value.generative.len];
 for index in 0..binders.len/2 {{ let propagated_error = ty(owner,binders[index*2]); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,binders[index*2+1]); if propagated_error != blot_error::Error.none { return propagated_error; } }let selected=owner.graph.nodes[binders[index*2+1]];{ let propagated_error = require(owner.graph.nodes[binders[index*2]].tag==blot_check_types::Tag.function&&selected.tag==blot_check_types::Tag.scoped&&selected.b==0&&owner.graph.nodes[selected.c].tag==blot_check_types::Tag.instance_selection); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 return blot_error::Error.none;
}
fn predicateTypes(owner:const Interface&,value:blot_check_types::Obligation)->Error {{ let propagated_error = ty(owner,value.ty); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,value.other); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,value.result); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,value.signature); if propagated_error != blot_error::Error.none { return propagated_error; } }return blot_error::Error.none;}
fn validate(owner:const Interface&,symbol_count:i64,unit_count:i64)->Error {
 for value in owner.obligations {{ let propagated_error = callee(owner,value,true,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for value in owner.contract_predicates {{ let propagated_error = callee(owner,value,false,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}for value in owner.implementation_predicates {{ let propagated_error = callee(owner,value,false,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}for value in owner.graph.quantifier_obligations {{ let propagated_error = callee(owner,value,false,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for proof in owner.selected_proofs {{ let propagated_error = callee(owner,proof.predicate,false,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 { let propagated_error = require(owner.has_numeric_proofs||owner.proof_contracts.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for value in owner.proof_contracts {{ let propagated_error = require(value.binding!=0&&value.binding<owner.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 if owner.capability_contracts.validate(owner.bindings.len,symbol_count)!=blot_error::Error.none {return blot_error::Error.invalid_artifact;}
 for entry in owner.capability_contracts.bindings {
  let binding=owner.bindings[entry.binding];{ let propagated_error = require(binding.capability_parameters.present()&&binding.kind==blot_reuse_principal_interface::Kind.global); if propagated_error != blot_error::Error.none { return propagated_error; } }
  let header=owner.capability_contracts.header(entry.binding,binding.capability_parameters.arity() as u32);assert(header.present);
  if header.value.view().validate(header.value.root,header.value.arity,true)!=blot_error::Error.none {return blot_error::Error.invalid_artifact;}
 }
 { let propagated_error = require(owner.unit!=0&&owner.unit<=unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(owner.graph.nodes.len>=6&&owner.graph.rows.len!=0&&owner.graph.operations.len>=2); if propagated_error != blot_error::Error.none { return propagated_error; } }
 { let propagated_error = blot_check_quantifier_goals::validate(owner.graph.nodes,owner.graph.quantifier_goals,owner.graph.quantifier_obligations); if propagated_error != blot_error::Error.none { return propagated_error; } }
 let prefix:Tag[6]=[blot_check_types::Tag.absent,blot_check_types::Tag.unit,blot_check_types::Tag.boolean,blot_check_types::Tag.unsigned32,blot_check_types::Tag.floating32,blot_check_types::Tag.never];
 for tag,index in prefix {let node=owner.graph.nodes[index];{ let propagated_error = require(node.tag==tag&&node.a==0&&node.b==0&&node.c==0); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for node in owner.graph.nodes {
  match node.tag {
   bound=>{if node.b==0 {{ let propagated_error = require(owner.has_rank_contracts&&node.a<128&&node.c==0); if propagated_error != blot_error::Error.none { return propagated_error; } }}else if node.c==0 {{ let propagated_error = require(owner.has_rank_contracts&&node.a<128&&(node.b==1||(owner.has_usage_contracts&&node.b==2))); if propagated_error != blot_error::Error.none { return propagated_error; } }}else {{ let propagated_error = require(owner.has_usage_contracts&&node.a==0&&node.b==2&&node.c<owner.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
   forall,existential=>{{ let propagated_error = require(owner.has_rank_contracts); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,List {node.b,node.c, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   rigid=>{return blot_error::Error.invalid_artifact;},
   instance_version=>{{ let propagated_error = units(node.a,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(node.a!=0&&node.b!=0&&node.b<0x04000000&&node.c<16); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   instance_selection=>{
    { let propagated_error = units(node.a,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(node.a!=0&&node.b!=0&&node.c<owner.graph.extra.len&&owner.graph.extra[node.c]==3); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = require(node.c!=0xffffffff); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,List {node.c+1,3, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }let children=owner.graph.extra[node.c+1..node.c+4];
    { let propagated_error = require(owner.graph.nodes[children[0]].tag==blot_check_types::Tag.scoped&&owner.graph.nodes[children[1]].tag==blot_check_types::Tag.scoped&&owner.graph.nodes[children[2]].tag==blot_check_types::Tag.instance_version); if propagated_error != blot_error::Error.none { return propagated_error; } }
   },
   usage=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(owner.has_usage_contracts&&node.b<=6); if propagated_error != blot_error::Error.none { return propagated_error; } }if node.c!=0 {{ let propagated_error = ty(owner,node.c); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
   erased_proof=>{{ let propagated_error = require(owner.has_numeric_proofs&&node.a==0&&node.b==0&&node.c==0); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   scoped=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,node.c); if propagated_error != blot_error::Error.none { return propagated_error; } }let region=owner.graph.nodes[node.c];{ let propagated_error = require(node.b==0&&(region.tag==blot_check_types::Tag.variable||region.tag==blot_check_types::Tag.instance_selection||(region.tag==blot_check_types::Tag.bound&&region.b==2))&&owner.graph.nodes[node.a].tag==blot_check_types::Tag.nominal); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   absent,unit,boolean,unsigned32,floating32,never=>{},
   variable=>{{ let propagated_error = require(node.b==0&&node.c==0); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   function=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,node.b); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(node.c<owner.graph.rows.len); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   product=>{{ let propagated_error = typeList(owner,List {node.a,node.b, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   record=>{
    { let propagated_error = require(node.b<=0x7fffffff); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(node.a,node.b*2,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for index in 0..node.b {let name=owner.graph.extra[node.a+index*2];{ let propagated_error = require(name!=0&&name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,owner.graph.extra[node.a+index*2+1]); if propagated_error != blot_error::Error.none { return propagated_error; } }}
   },
   nominal,projection=>{
    { let propagated_error = identity(blot_check_types::NominalIdentity {node.a,node.b, ..},symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(node.c<owner.graph.extra.len&&node.c!=0xffffffff); if propagated_error != blot_error::Error.none { return propagated_error; } }
    let count=owner.graph.extra[node.c];let start=node.c+1;{ let propagated_error = typeList(owner,List {start,count, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if node.tag==blot_check_types::Tag.projection {
     { let propagated_error = require(count<=0xffffffff-start); if propagated_error != blot_error::Error.none { return propagated_error; } }let slot=start+count;{ let propagated_error = require(slot<owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }let member_name=owner.graph.extra[slot];{ let propagated_error = require(member_name!=0&&member_name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
     var declared=false;for member in owner.contract_members {if member.contract.unit==node.a&&member.contract.decl==node.b&&member.name==member_name&&member.kind!=blot_reuse_principal_interface::ContractMemberKind.value {declared=true;}}{ let propagated_error = require(declared); if propagated_error != blot_error::Error.none { return propagated_error; } }
     var selected=false;for candidate in owner.contracts {if candidate.identity.unit==node.a&&candidate.identity.decl==node.b {{ let propagated_error = require(count==candidate.parameters.len); if propagated_error != blot_error::Error.none { return propagated_error; } }selected=true;break;}}{ let propagated_error = require(selected); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
   },
   type_constructor=>{{ let propagated_error = identity(blot_check_types::NominalIdentity {node.a,node.b, ..},symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   array,list,cursor,resolver=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   provider=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(node.c<owner.graph.rows.len); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   state_provider=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,node.b); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,node.c); if propagated_error != blot_error::Error.none { return propagated_error; } }},
  }
 }
 { let propagated_error = require(owner.graph.row_variable_count<=blot_check_effects::formal_key_bit); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for row in owner.graph.rows {
  { let propagated_error = require(row.cursor==0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(row.labels.start,row.labels.len,owner.graph.labels.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
  for label in owner.graph.labels[row.labels.start..row.labels.start+row.labels.len] {{ let propagated_error = require(label!=0&&label<owner.graph.operations.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  match row.tail {
   variable value=>{{ let propagated_error = require(value.value<owner.graph.row_variable_count); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   formal value=>{{ let propagated_error = ty(owner,value.value); if propagated_error != blot_error::Error.none { return propagated_error; } }let leaf=owner.graph.nodes[value.value];{ let propagated_error = require(leaf.tag==blot_check_types::Tag.bound&&leaf.b==1&&leaf.c==0); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   _=>{},
  }
 }
 { let propagated_error = require(owner.graph.rows[0].labels.len==0&&owner.graph.rows[0].tail==blot_check_effects::Tail.closed); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for operation in owner.graph.operations {
  { let propagated_error = require(operation.instance.unit==0); if propagated_error != blot_error::Error.none { return propagated_error; } }if operation.instance.decl!=0 {{ let propagated_error = ty(owner,operation.instance.decl); if propagated_error != blot_error::Error.none { return propagated_error; } }let tag=owner.graph.nodes[operation.instance.decl].tag;{ let propagated_error = require(tag==blot_check_types::Tag.variable||tag==blot_check_types::Tag.instance_selection); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  { let propagated_error = identity(operation.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,operation.arguments); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 { let propagated_error = require(owner.graph.operations[0].identity.unit==0&&owner.graph.operations[0].identity.decl==0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(owner.graph.operations[1].identity.unit==0&&owner.graph.operations[1].identity.decl==1); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for node in owner.patterns.nodes {
  match node.kind {
   binding=>{{ let propagated_error = ty(owner,node.a); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   tuple,array=>{{ let propagated_error = patternList(owner,List {node.a,node.b, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }},
   record=>{
    { let propagated_error = require(node.b<=0x7fffffff); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(node.a,node.b*2,owner.patterns.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    for index in 0..node.b {{ let propagated_error = require(owner.patterns.extra[node.a+index*2]<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(owner.patterns.extra[node.a+index*2+1]<owner.patterns.nodes.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}
   },
  }
 }
 for binding in owner.bindings {
  { let propagated_error = require(binding.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(blot_check_capability_flow::contractCode(binding.capability_flow)<=blot_check_capability_flow::contractCode(blot_check_capability_flow::Contract.spawn_task)); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = ty(owner,binding.ty); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = scheme(owner,binding.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(binding.capability_parameters.valid()); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if binding.capability_flow==blot_check_capability_flow::Contract.input_shape {{ let propagated_error = require(binding.capability_parameters.kind==blot_check_capability_flow::ParameterResult.product&&binding.capability_parameters.arity()!=0&&binding.scheme.generative.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  if binding.capability_flow!=blot_check_capability_flow::Contract.unknown||binding.capability_parameters.present() {
   { let propagated_error = require(!binding.external.present&&(binding.named_function||binding.capability_flow==blot_check_capability_flow::Contract.consume_task||binding.capability_flow==blot_check_capability_flow::Contract.spawn_task)); if propagated_error != blot_error::Error.none { return propagated_error; } }
   { let propagated_error = require(binding.scheme.root!=0); if propagated_error != blot_error::Error.none { return propagated_error; } }var root=binding.scheme.root;if owner.graph.nodes[root].tag==blot_check_types::Tag.forall {{ let propagated_error = require(owner.has_rank_contracts); if propagated_error != blot_error::Error.none { return propagated_error; } }root=owner.graph.nodes[root].a;}{ let propagated_error = require(owner.graph.nodes[root].tag==blot_check_types::Tag.function); if propagated_error != blot_error::Error.none { return propagated_error; } }
  }
  if binding.external.present {{ let propagated_error = target(owner,binding.external.value,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(binding.external.value.binding!=0); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 }
 { let propagated_error = require(owner.obligations.len==owner.obligation_spans.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for obligation in owner.obligations {
  { let propagated_error = ty(owner,obligation.ty); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,obligation.result); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,obligation.other); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,obligation.signature); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = require(obligation.source==0&&obligation.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(obligation.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = units(obligation.qualification_unit,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 for nominal in owner.nominals {
  { let propagated_error = require(!nominal.affine||nominal.has_usage); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(!nominal.closed_storage||!nominal.has_usage); if propagated_error != blot_error::Error.none { return propagated_error; } }if nominal.has_usage {{ let propagated_error = require(owner.has_usage_contracts); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  if nominal.identity.unit!=0&&nominal.identity.unit!=0xffffffff {{ let propagated_error = require(nominal.is_opaque==(nominal.identity.decl&blot_check_types::opaque_name_bit!=0)); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  if nominal.is_opaque {{ let propagated_error = require(nominal.alias==0&&nominal.constructors.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(nominal.storage.kind!=blot_backend_opaque_storage::Kind.parameter||nominal.storage.parameter<nominal.parameters.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(nominal.identity.decl&blot_check_types::opaque_name_bit!=0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require((nominal.identity.decl&~blot_check_types::opaque_name_bit)<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  { let propagated_error = ty(owner,nominal.alias); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,nominal.alias_rows,owner.graph.row_variable_count); if propagated_error != blot_error::Error.none { return propagated_error; } }if nominal.alias!=0 {{ let propagated_error = require(nominal.constructors.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  { let propagated_error = identity(nominal.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(nominal.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,nominal.parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,nominal.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = patternList(owner,nominal.patterns); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,nominal.parameter_names,symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,nominal.constructors,owner.constructors.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 for contract in owner.contracts {
  { let propagated_error = identity(contract.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(contract.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,contract.parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = variableList(owner,contract.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,contract.row_variables,owner.graph.row_variable_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,contract.parameter_names,symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,contract.row_parameter_names,symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = require(contract.row_parameters.len==contract.row_parameter_names.len&&contract.declaration==0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(contract.row_parameters.start,contract.row_parameters.len,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = range(contract.row_variables.start,contract.row_variables.len,owner.graph.extra.len); if propagated_error != blot_error::Error.none { return propagated_error; } }let variables=owner.graph.extra[contract.row_variables.start..contract.row_variables.start+contract.row_variables.len];
  for row in owner.graph.extra[contract.row_parameters.start..contract.row_parameters.start+contract.row_parameters.len] {
   { let propagated_error = require(row<owner.graph.rows.len); if propagated_error != blot_error::Error.none { return propagated_error; } }let value=owner.graph.rows[row];var variable:u32=0;match value.tail {variable item=>{variable=item.value;},_=>{return blot_error::Error.invalid_artifact;}}{ let propagated_error = require(value.labels.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }
   var bound=false;for candidate in variables {if candidate==variable {bound=true;break;}}{ let propagated_error = require(bound); if propagated_error != blot_error::Error.none { return propagated_error; } }
  }
  let row_names=owner.graph.extra[contract.row_parameter_names.start..contract.row_parameter_names.start+contract.row_parameter_names.len];
  for name,ordinal in row_names {{ let propagated_error = require(name!=0); if propagated_error != blot_error::Error.none { return propagated_error; } }for previous in row_names[..ordinal] {{ let propagated_error = require(name!=previous); if propagated_error != blot_error::Error.none { return propagated_error; } }}}
  { let propagated_error = require(contract.parameter_names.len==contract.variables.len&&contract.patterns.len==contract.parameters.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = patternList(owner,contract.patterns); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = range(contract.predicates.start,contract.predicates.len,owner.contract_predicates.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(contract.members.start,contract.members.len,owner.contract_members.len); if propagated_error != blot_error::Error.none { return propagated_error; } }var requires_implementation=false;
  for member,index in owner.contract_members[contract.members.start..contract.members.start+contract.members.len] {
   { let propagated_error = require(member.contract==contract.identity); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(member.name!=0&&member.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,member.root); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require((member.kind==blot_reuse_principal_interface::ContractMemberKind.abstract_type)==(member.root==0)); if propagated_error != blot_error::Error.none { return propagated_error; } }
   if member.kind==blot_reuse_principal_interface::ContractMemberKind.value {{ let propagated_error = require(owner.graph.nodes[member.root].tag==blot_check_types::Tag.function); if propagated_error != blot_error::Error.none { return propagated_error; } }}
   for previous in owner.contract_members[contract.members.start..contract.members.start+index] {{ let propagated_error = require(previous.name!=member.name); if propagated_error != blot_error::Error.none { return propagated_error; } }}
   requires_implementation=requires_implementation||member.kind!=blot_reuse_principal_interface::ContractMemberKind.defined_type;
  }
  { let propagated_error = require(contract.requires_implementation==requires_implementation); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 for predicate in owner.contract_predicates {{ let propagated_error = predicateTypes(owner,predicate); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(predicate.source==0&&predicate.name<symbol_count&&predicate.explicit); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(predicate.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = units(predicate.qualification_unit,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 { let propagated_error = require(owner.implementations.len<=4096); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for implementation in owner.implementations {
  { let propagated_error = identity(implementation.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(implementation.contract,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(implementation.name<symbol_count&&implementation.declaration==0); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if implementation.private&&implementation.name==0 {{ let propagated_error = require(implementation.head.len==0&&implementation.variables.len==0&&implementation.row_variables.len==0&&implementation.predicates.len==0&&implementation.members.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }continue;}
  { let propagated_error = require(implementation.name!=0&&implementation.identity.decl==(blot_check_types::opaque_name_bit|implementation.name)); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = typeList(owner,implementation.head); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = variableList(owner,implementation.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,implementation.parameter_names,symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,implementation.row_parameter_names,symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = require(implementation.parameter_names.len==implementation.variables.len&&implementation.row_parameter_names.len==implementation.row_variables.len&&implementation.row_parameters.len==implementation.row_variables.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = namesList(owner,implementation.row_variables,owner.graph.row_variable_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,implementation.row_parameters,owner.graph.rows.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(implementation.predicates.start,implementation.predicates.len,owner.implementation_predicates.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(implementation.members.start,implementation.members.len,owner.implementation_members.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 for member in owner.implementation_members {
  { let propagated_error = require(member.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,member.root); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = target(owner,member.target,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }
  if member.kind==blot_reuse_principal_interface::ImplementationMemberKind.type_ {{ let propagated_error = require(member.target.unit==0&&member.target.binding==0); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  if member.name!=0&&member.kind==blot_reuse_principal_interface::ImplementationMemberKind.value {{ let propagated_error = require(member.target.binding!=0&&owner.graph.nodes[member.root].tag==blot_check_types::Tag.function); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 }
 for predicate in owner.implementation_predicates {{ let propagated_error = predicateTypes(owner,predicate); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(predicate.source==0&&predicate.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(predicate.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for template in owner.member_templates {{ let propagated_error = require(template.binding!=0&&template.binding<owner.bindings.len&&template.name!=0&&template.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(template.contract,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,template.arguments); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for member in owner.selected_members {{ let propagated_error = require(member.name!=0&&member.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,member.root); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(member.root!=0); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = target(owner,member.target,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for proof,ordinal in owner.selected_proofs {
  { let propagated_error = target(owner,proof.predicate_target,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }if proof.predicate_target.binding==0 {{ let propagated_error = require(proof.predicate_target.unit==0); if propagated_error != blot_error::Error.none { return propagated_error; } }}{ let propagated_error = units(proof.context,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(proof.implementation,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = identity(proof.contract,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,proof.arguments); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = predicateTypes(owner,proof.predicate); if propagated_error != blot_error::Error.none { return propagated_error; } }
  { let propagated_error = range(proof.members.start,proof.members.len,owner.selected_members.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = range(proof.prerequisites.start,proof.prerequisites.len,owner.selected_edges.len); if propagated_error != blot_error::Error.none { return propagated_error; } }for child in owner.selected_edges[proof.prerequisites.start..proof.prerequisites.start+proof.prerequisites.len] {{ let propagated_error = require(child<ordinal); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 }
 for constructor in owner.constructors {{ let propagated_error = identity(constructor.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(constructor.name<symbol_count&&constructor.nominal<owner.nominals.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = scheme(owner,constructor.scheme); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,constructor.payload); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for family in owner.effect_families {{ let propagated_error = identity(family.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(family.name<symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,family.parameters); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = typeList(owner,family.variables); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = patternList(owner,family.patterns); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,family.parameter_names,symbol_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = namesList(owner,family.operations,owner.effect_templates.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for operation in owner.effect_templates {{ let propagated_error = identity(operation.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(operation.name<symbol_count&&operation.family<owner.effect_families.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,operation.parameter); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = ty(owner,operation.result); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 for method in owner.associated {{ let propagated_error = identity(method.identity,symbol_count,unit_count); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(method.member<symbol_count&&method.binding<owner.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 return blot_error::Error.none;
}

// Bounds admission precedes graph traversal; none of these edges repair input.
struct GraphEdges {owner:const Interface&}
fn rowStart(self_:GraphEdges)->i64 {return self_.owner.graph.nodes.len;}
fn operationStart(self_:GraphEdges)->i64 {return self_.rowStart()+self_.owner.graph.rows.len;}
fn patternStart(self_:GraphEdges)->i64 {return self_.operationStart()+self_.owner.graph.operations.len;}
fn total(self_:GraphEdges)->i64 {return self_.patternStart()+self_.owner.patterns.nodes.len;}
fn absentEdge()->blot_support::Option<i64> {return blot_support::none<i64>();}
fn edge(value:i64)->blot_support::Option<i64> {return blot_support::some(value);}
fn child(self_:GraphEdges,key:i64,index:i64)->blot_support::Option<i64> {
 let g=self_.owner.graph;
 if key<self_.rowStart() {
  let n=g.nodes[key];
  match n.tag {
   usage=>{if index==0 {return edge(n.a);}if index==1&&n.c!=0 {return edge(n.c);}return absentEdge();},
   function=>{if index==0 {return edge(n.a);}if index==1 {return edge(n.b);}if index==2 {return edge(self_.rowStart()+n.c);}return absentEdge();},
   forall,existential=>{
    if index==0 {return edge(n.a);}if index-1<n.c {return edge(g.extra[n.b+index-1]);}
    let goals=blot_check_quantifier_goals::get(g.quantifier_goals,g.quantifier_obligations,key as u32);let slot=index-1-n.c;
    if slot/4>=goals.len {return absentEdge();}let goal=goals[slot/4];let children:u32[4]=[goal.ty,goal.other,goal.result,goal.signature];return edge(children[slot%4]);
   },
   product=>{if index<n.b {return edge(g.extra[n.a+index]);}return absentEdge();},
   record=>{if index<n.b {return edge(g.extra[n.a+index*2+1]);}return absentEdge();},
   nominal=>{if index<g.extra[n.c] {return edge(g.extra[n.c+1+index]);}return absentEdge();},
   projection=>{
    let count=g.extra[n.c];if index<count {return edge(g.extra[n.c+1+index]);}if index!=count {return absentEdge();}let member_name=g.extra[n.c+1+count];
    for member in self_.owner.contract_members {if member.contract.unit==n.a&&member.contract.decl==n.b&&member.name==member_name&&member.kind==blot_reuse_principal_interface::ContractMemberKind.defined_type {return edge(member.root);}}
    return absentEdge();
   },
   array,list,cursor,resolver=>{if index==0 {return edge(n.a);}return absentEdge();},
   provider=>{if index==0 {return edge(n.a);}if index==1 {return edge(self_.rowStart()+n.c);}return absentEdge();},
   state_provider=>{if index==0 {return edge(n.a);}if index==1 {return edge(n.b);}if index==2 {return edge(n.c);}return absentEdge();},
   _=>{return absentEdge();},
  }
 }
 if key<self_.operationStart() {let row=g.rows[key-self_.rowStart()];if index<row.labels.len {return edge(self_.operationStart()+g.labels[row.labels.start+index]);}return absentEdge();}
 if key<self_.patternStart() {let operation=g.operations[key-self_.operationStart()];if index<operation.arguments.len {return edge(g.extra[operation.arguments.start+index]);}return absentEdge();}
 let p=self_.owner.patterns;let n=p.nodes[key-self_.patternStart()];
 match n.kind {
  binding=>{if index==0 {return edge(n.a);}return absentEdge();},
  tuple,array=>{if index<n.b {return edge(self_.patternStart()+p.extra[n.a+index]);}return absentEdge();},
  record=>{if index<n.b {return edge(self_.patternStart()+p.extra[n.a+index*2+1]);}return absentEdge();},
 }
}
struct Frame {key:i64=0,next:i64=0}
fn validateGraph(owner:const Interface&)->Error {var remaining:i64=1000000;return validateGraphWithBudget(owner,remaining);}
fn validateGraphWithBudget(owner:const Interface&,remaining:i64&)->Error {
 if owner.has_numeric_proofs {{ let propagated_error = blot_check_numeric_proof_core::dataTypes(blot_check_frozen_types::Source.frozen {owner.graph, ..},owner.graph.nodes); if propagated_error != blot_error::Error.none { return propagated_error; } }}
 { let propagated_error = require(owner.has_numeric_proofs||owner.proof_contracts.len==0); if propagated_error != blot_error::Error.none { return propagated_error; } }
 // All growing owners below stay outside the recursive proof/checker cycles.
 var terms:blot_check_numeric_proof_terms::Term[>..]=[];var term_index = blot_check_numeric_proof_terms::TermIndex {..};
 var proof_budget=blot_check_numeric_proof_terms::init(terms,term_index);proof_budget.limits.visits=min(remaining,proof_budget.limits.visits);
 var proof_bindings:dictionary<u32,bool> =dictionary<u32,bool> {};
 for value in owner.proof_contracts {
  { let propagated_error = require(value.binding!=0&&value.binding<owner.bindings.len); if propagated_error != blot_error::Error.none { return propagated_error; } }{ let propagated_error = require(!proof_bindings.contains(value.binding)); if propagated_error != blot_error::Error.none { return propagated_error; } }proof_bindings.insert(value.binding,true);
  let signature_error=value.header.signature().validateInto(proof_budget);if signature_error==blot_error::Error.out_of_memory {return signature_error;}if signature_error!=blot_error::Error.none {return blot_error::Error.invalid_artifact;}
  { let propagated_error = blot_check_numeric_proof_core::signatureTypes(blot_check_frozen_types::Source.frozen {owner.graph, ..},owner.bindings[value.binding].ty,value.header); if propagated_error != blot_error::Error.none { return propagated_error; } }
 }
 remaining-=min(remaining,proof_budget.visits);terms.clear();proof_budget.deinit();
 { let propagated_error = blot_check_associated_admission::interfaceWithBudget(owner,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }let source=blot_check_associated_admission::typesView(owner.graph);
 { let propagated_error = blot_eval_implementation_admission::scopes(source,owner,owner.implementation_predicates,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
 var symbol_limit:i64=0;
 for n in owner.graph.nodes {if n.tag==blot_check_types::Tag.record {for index in 0..n.b {symbol_limit=max(symbol_limit,(owner.graph.extra[n.a+index*2] as i64)+1);}}}
 var stamps:u32[>..<]=[];stamps.resize(symbol_limit,0);var generation:u32=0;
 for n in owner.graph.nodes {
  if n.tag!=blot_check_types::Tag.record {continue;}if generation==0xffffffff {return blot_error::Error.invalid_artifact;}generation++;
  for index in 0..n.b {let name=owner.graph.extra[n.a+index*2];if stamps[name]==generation {return blot_error::Error.invalid_artifact;}stamps[name]=generation;}
 }
 let graph=GraphEdges {owner, ..};let count=graph.total();var colors:u8[>..<]=[];colors.resize(count,0);var frames:Frame[>..<]=[];frames.resize(count,Frame {..});
 for root in 0..count {
  if colors[root]!=0 {continue;}var depth:i64=1;frames[0]=Frame {key:root, ..};colors[root]=1;
  while depth!=0 {
   let current:Frame& =frames[depth-1];let next=graph.child(current.key,current.next);
   if !next.present {colors[current.key]=2;depth--;continue;}current.next++;
   let child=next.value;if colors[child]==1 {return blot_error::Error.invalid_artifact;}if colors[child]==2 {continue;}
   colors[child]=1;frames[depth]=Frame {key:child, ..};depth++;
  }
 }
 return blot_check_rank_portable::interface(owner);
}
