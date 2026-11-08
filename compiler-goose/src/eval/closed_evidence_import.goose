namespace blot_eval_closed_evidence_import;
import check.effect_evidence;
import check.effects;
import check.types;
import eval.semantic_evidence_import;
import eval.type_evidence;
import support.error;
import support.native;
import support.pooled_buffer;

import dictionary;
type Error=blot_error::Error;
type Tag=blot_eval_type_evidence::Tag;
struct Frame { start: u32,len: u32 }
struct Importer { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View,destination: blot_check_types::Store,types: dictionary<u32,u32>&,rows: dictionary<u32,u32>&,binders: u32[>..<]&,frames: Frame[128],scope_count: i64=0 }
fn ty<I>(self_: I&,id: u32,depth: i64) -> u32,Error { var arguments=Words {}; var goals=Goals {}; var children=Words {}; var fields=Fields {}; let value,error=tyInner(self_,id,depth,arguments,goals,children,fields); arguments.deinit(); goals.deinit(); children.deinit(); fields.deinit(); return value,error; }
fn tyInner<I>(self_: I&,id: u32,depth: i64,arguments: Words&,goals: Goals&,copied_children: Words&,field_values: Fields&) -> u32,Error {
 let destination=target(self_);
 if id<=5 { return id,blot_error::Error.none; } if depth>=256 { return 0,blot_error::Error.type_limit; }
 if self_.scope_count==0 { let known=self_.types.get(id); if known { return known,blot_error::Error.none; } }
 let e=destination.chargeProjection(); if e!=blot_error::Error.none { return 0,e; } let n=self_.source.node(id); let tag=n.tag; var result: u32=0;
 if tag==blot_eval_type_evidence::Tag.scoped { let base,err=ty(self_,n.a,depth+1); if err!=blot_error::Error.none { return 0,err; } let value,error=destination.scoped(base,blot_check_types::NominalIdentity {n.b,n.c}); if error!=blot_error::Error.none { return 0,error; } result=value; }
 else if tag==blot_eval_type_evidence::Tag.erased_proof { let value,error=destination.proofKind(); if error!=blot_error::Error.none { return 0,error; } result=value; }
 else if tag==blot_eval_type_evidence::Tag.projection {
  let descriptor=self_.source.projection(id); if descriptor.scope>=self_.scope_count { return 0,blot_error::Error.type_mismatch; }
  for arg in self_.source.children(id) { let value,err=ty(self_,arg,depth+1); if err!=blot_error::Error.none { return 0,err; } arguments.push(value); }
  if arguments.failure!=blot_error::Error.none { return 0,arguments.failure; } let value,error=destination.projection(blot_check_types::NominalIdentity {n.a,n.b},descriptor.member,arguments.items); if error!=blot_error::Error.none { return 0,error; } result=value;
 } else if tag==blot_eval_type_evidence::Tag.bound {
  if n.c>=self_.scope_count { return 0,blot_error::Error.type_mismatch; } let frame=self_.frames[self_.scope_count-1-n.c]; if n.a>=frame.len { return 0,blot_error::Error.type_mismatch; }
  result=binderValues(self_)[frame.start+n.a]; if destination.node(result).b!=n.b { return 0,blot_error::Error.type_mismatch; }
 } else if tag==blot_eval_type_evidence::Tag.forall||tag==blot_eval_type_evidence::Tag.existential {
  if n.b==0||n.b>128||self_.scope_count==128 { return 0,blot_error::Error.type_limit; } let first=binderLength(self_);
  for formal,ordinal in self_.source.children(id) { let leaf=self_.source.node(formal); if leaf.tag!=blot_eval_type_evidence::Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { return 0,blot_error::Error.type_mismatch; } let value,err=destination.boundType(ordinal as u32,leaf.b); if err!=blot_error::Error.none { return 0,err; } let pushed=pushBinder(self_,value); if pushed!=blot_error::Error.none { return 0,pushed; } }
  self_.frames[self_.scope_count]=Frame {first as u32,n.b}; self_.scope_count++;

  for goal in self_.source.quantifierGoals(id) {
   let err=destination.chargeProjection(); if err!=blot_error::Error.none { let __cleanup_result_142_0: u32 = 0; let __cleanup_result_142_1: Error = err; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_142_0, __cleanup_result_142_1; }
   var value=blot_check_types::Obligation {ty:0,kind:goal.kind,source:0,name:goal.name,operator:goal.operator,identity:goal.identity,explicit:goal.explicit};
   if goal.ty!=0 { let v,e1=ty(self_,goal.ty,depth+1); if e1!=blot_error::Error.none { let __cleanup_result_143_0: u32 = 0; let __cleanup_result_143_1: Error = e1; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_143_0, __cleanup_result_143_1; } value.ty=v; } if goal.other!=0 { let v,e2=ty(self_,goal.other,depth+1); if e2!=blot_error::Error.none { let __cleanup_result_144_0: u32 = 0; let __cleanup_result_144_1: Error = e2; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_144_0, __cleanup_result_144_1; } value.other=v; } if goal.result!=0 { let v,e3=ty(self_,goal.result,depth+1); if e3!=blot_error::Error.none { let __cleanup_result_145_0: u32 = 0; let __cleanup_result_145_1: Error = e3; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_145_0, __cleanup_result_145_1; } value.result=v; } if goal.signature!=0 { let v,e4=ty(self_,goal.signature,depth+1); if e4!=blot_error::Error.none { let __cleanup_result_146_0: u32 = 0; let __cleanup_result_146_1: Error = e4; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_146_0, __cleanup_result_146_1; } value.signature=v; } goals.push(value);
  }
  let body,err=ty(self_,n.a,depth+1); if err!=blot_error::Error.none { let __cleanup_result_147_0: u32 = 0; let __cleanup_result_147_1: Error = err; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_147_0, __cleanup_result_147_1; } var result_tag=blot_check_types::Tag.existential; if tag==blot_eval_type_evidence::Tag.forall { result_tag=blot_check_types::Tag.forall; }
  if goals.failure!=blot_error::Error.none { self_.scope_count--; resizeBinders(self_,first); return 0,goals.failure; } let value,error=destination.quantifiedWithGoals(result_tag,body,binderValues(self_)[first..first+n.b],goals.items); if error!=blot_error::Error.none { let __cleanup_result_148_0: u32 = 0; let __cleanup_result_148_1: Error = error; { self_.scope_count--; resizeBinders(self_,first); } return __cleanup_result_148_0, __cleanup_result_148_1; } result=value;
  { self_.scope_count--; resizeBinders(self_,first); } } else if tag==blot_eval_type_evidence::Tag.usage {
  let base,err=ty(self_,n.a,depth+1); if err!=blot_error::Error.none { return 0,err; } var region: u32=0; if n.c!=0 { let value,error=ty(self_,n.c,depth+1); if error!=blot_error::Error.none { return 0,error; } region=value; }
  let usage,known=blot_check_types::usageKindFromCode(n.b as u32); if !known { return 0,blot_error::Error.type_mismatch; } let value,error=destination.usage(base,usage,region); if error!=blot_error::Error.none { return 0,error; } result=value;
 } else if tag==blot_eval_type_evidence::Tag.function {
  let input,e1=ty(self_,n.a,depth+1); if e1!=blot_error::Error.none { return 0,e1; } let output,e2=ty(self_,n.b,depth+1); if e2!=blot_error::Error.none { return 0,e2; } let effects,e3=row(self_,n.c,depth+1); if e3!=blot_error::Error.none { return 0,e3; } let value,error=destination.functionWithEffects(input,output,effects); if error!=blot_error::Error.none { return 0,error; } result=value;
 } else if tag==blot_eval_type_evidence::Tag.array||tag==blot_eval_type_evidence::Tag.list||tag==blot_eval_type_evidence::Tag.cursor||tag==blot_eval_type_evidence::Tag.resolver||tag==blot_eval_type_evidence::Tag.provider {
  let base,err=ty(self_,n.a,depth+1); if err!=blot_error::Error.none { return 0,err; }
  if tag==blot_eval_type_evidence::Tag.resolver { let value,error=destination.resolver(base); if error!=blot_error::Error.none { return 0,error; } result=value; }
  else if tag==blot_eval_type_evidence::Tag.provider { let effects,e=row(self_,n.c,depth+1); if e!=blot_error::Error.none { return 0,e; } let value,error=destination.provider(base,effects); if error!=blot_error::Error.none { return 0,error; } result=value; }
  else { var sequence=blot_check_types::Tag.array; if tag==blot_eval_type_evidence::Tag.list { sequence=blot_check_types::Tag.list; } else if tag==blot_eval_type_evidence::Tag.cursor { sequence=blot_check_types::Tag.cursor; } let value,error=destination.sequence(sequence,base); if error!=blot_error::Error.none { return 0,error; } result=value; }
 } else if tag==blot_eval_type_evidence::Tag.state_provider {
  let read,e1=ty(self_,n.a,depth+1); if e1!=blot_error::Error.none { return 0,e1; } let write,e2=ty(self_,n.b,depth+1); if e2!=blot_error::Error.none { return 0,e2; } let state,e3=ty(self_,n.c,depth+1); if e3!=blot_error::Error.none { return 0,e3; } let value,error=destination.stateProvider(read,write,state); if error!=blot_error::Error.none { return 0,error; } result=value;
 } else if tag==blot_eval_type_evidence::Tag.type_constructor { let value,error=destination.typeConstructor(blot_check_types::NominalIdentity {n.a,n.b}); if error!=blot_error::Error.none { return 0,error; } result=value; }
 else if tag==blot_eval_type_evidence::Tag.product||tag==blot_eval_type_evidence::Tag.nominal {
   for child in self_.source.children(id) { let value,e=ty(self_,child,depth+1); if e!=blot_error::Error.none { return 0,e; } copied_children.push(value); }
  if copied_children.failure!=blot_error::Error.none { return 0,copied_children.failure; } if tag==blot_eval_type_evidence::Tag.nominal { let value,error=destination.nominal(blot_check_types::NominalIdentity {n.a,n.b},copied_children.items); if error!=blot_error::Error.none { return 0,error; } result=value; }
  else { let value,error=destination.product(copied_children.items); if error!=blot_error::Error.none { return 0,error; } result=value; }
 } else if tag==blot_eval_type_evidence::Tag.record {
   let children=self_.source.children(id); var at=0;
  while at<children.len { let value,e=ty(self_,children[at+1],depth+1); if e!=blot_error::Error.none { return 0,e; } field_values.push(blot_check_types::Field {children[at],value}); at+=2; } if field_values.failure!=blot_error::Error.none { return 0,field_values.failure; } let value,error=destination.record(field_values.items); if error!=blot_error::Error.none { return 0,error; } result=value;
 } else { return 0,blot_error::Error.type_mismatch; }
 if self_.scope_count==0 { self_.types.insert(id,result); } return result,blot_error::Error.none;
}
fn row<I>(self_: I&,id: u32,depth: i64) -> u32,Error { var labels=Words {}; var arguments=Words {}; let value,error=rowInner(self_,id,depth,labels,arguments); labels.deinit(); arguments.deinit(); return value,error; }
fn rowInner<I>(self_: I&,id: u32,depth: i64,labels: Words&,arguments: Words&) -> u32,Error {
 let destination=target(self_);
 if id==0 { return 0,blot_error::Error.none; } if depth>=256 { return 0,blot_error::Error.type_limit; } if self_.scope_count==0 { let known=self_.rows.get(id); if known { return known,blot_error::Error.none; } }
 let e=destination.chargeProjection(); if e!=blot_error::Error.none { return 0,e; }
 for label in self_.source.effects.rowLabels(id) { arguments.items=arguments.storage[..0];
  let err=destination.chargeProjection(); if err!=blot_error::Error.none { return 0,err; } let operation=self_.source.effects.operation(label);
  for argument in self_.source.effects.operationArguments(label) { let value,error=ty(self_,argument,depth+1); if error!=blot_error::Error.none { return 0,error; } arguments.push(value); }
  if arguments.failure!=blot_error::Error.none { return 0,arguments.failure; } let value,error=destination.internScopedOperation(operation.identity,operation.instance,arguments.items); if error!=blot_error::Error.none { return 0,error; } labels.push(value);
 }
 if labels.failure!=blot_error::Error.none { return 0,labels.failure; } var tail=blot_check_effects::Tail.closed; let formal=self_.source.effects.rows[id].formal;
 if formal!=0 { let value,error=ty(self_,formal,depth+1); if error!=blot_error::Error.none { return 0,error; } tail=blot_check_effects::Tail.formal {value:value}; }
 let result,err=destination.effects.row(labels.items,tail); if err!=blot_error::Error.none { return 0,blot_check_types::effectError(err); } if self_.scope_count==0 { self_.rows.insert(id,result); } return result,blot_error::Error.none;
}

type Words=blot_eval_semantic_evidence_import::WordBuffer;
type WordMap=blot_eval_semantic_evidence_import::WordMap;
struct Goals { storage: blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),items: blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),failure: Error=blot_error::Error.none }
struct Fields { storage: blot_check_types::Field[:]=default<blot_check_types::Field[:]>(),items: blot_check_types::Field[:]=default<blot_check_types::Field[:]>(),failure: Error=blot_error::Error.none }
reusable[] var goal_runs: blot_check_types::Obligation[>..]=[];
reusable[] var field_runs: blot_check_types::Field[>..]=[];
fn push(self_: Goals&,value: blot_check_types::Obligation) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,goal_runs); }
fn push(self_: Fields&,value: blot_check_types::Field) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,field_runs); }
fn deinit(self_: Goals&) { blot_support_pooled_buffer::deinit(self_,goal_runs); }
fn deinit(self_: Fields&) { blot_support_pooled_buffer::deinit(self_,field_runs); }
struct PooledImporter { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View=blot_eval_type_evidence::View {nodes:[],extra:[],effects:blot_check_effect_evidence::View {}},destination: blot_check_types::Store=blot_check_types::Store {},types: WordMap=WordMap {},rows: WordMap=WordMap {},binders: Words=Words {},frames: Frame[128]=[Frame {0,0};128],scope_count: i64=0 }
fn initPooled(source: blot_eval_type_evidence::View,destination: blot_check_types::Store&) -> PooledImporter { return PooledImporter {source:source,destination:destination}; }
fn deinit(self_: PooledImporter&) { self_.types.deinit(); self_.rows.deinit(); self_.binders.deinit(); self_.destination=blot_check_types::Store {}; self_.scope_count=0; self_.owner_id=0; }
fn deinit(self_: Importer&) { self_.types.clear(); self_.rows.clear(); self_.binders.clear(); self_.scope_count=0; self_.owner_id=0; }
fn target(self_: Importer&) -> blot_check_types::Store { return self_.destination; }
fn target(self_: PooledImporter&) -> blot_check_types::Store { if self_.destination.owner_id==0 { abort("inactive closed evidence importer"); } return self_.destination; }
fn binderLength(self_: Importer&) -> i64 { return self_.binders.len; }
fn binderLength(self_: PooledImporter&) -> i64 { return self_.binders.items.len; }
fn binderValues(self_: Importer&) -> const u32[:] { return self_.binders; }
fn binderValues(self_: PooledImporter&) -> const u32[:] { return self_.binders.items; }
fn pushBinder(self_: Importer&,value: u32) -> Error { self_.binders.push(value); return blot_error::Error.none; }
fn pushBinder(self_: PooledImporter&,value: u32) -> Error { self_.binders.push(value); return self_.binders.failure; }
fn resizeBinders(self_: Importer&,length: i64) { self_.binders.resize(length); }
fn resizeBinders(self_: PooledImporter&,length: i64) { assert(length>=0&&length<=self_.binders.items.len); self_.binders.items=self_.binders.storage[..length]; }
fn withImporter<C,F,R>(source: blot_eval_type_evidence::View,destination: blot_check_types::Store,context: C&) -> R,Error { var importer=initPooled(source,destination); let result,error=F(context,importer); importer.deinit(); return result,error; }
