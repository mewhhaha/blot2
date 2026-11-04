namespace blot_eval_closed_evidence_import;
import dictionary;
import .type_evidence;
import check.types;
import check.effects;
import support.error;
import support.native;
type Error=blot_error::Error;
type Tag=blot_eval_type_evidence::Tag;
struct Frame { start: u32,len: u32 }
struct Importer { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View,destination: blot_check_types::Store&,types: dictionary<u32,u32>&,rows: dictionary<u32,u32>&,binders: u32[>..<]&,frames: Frame[128],scope_count: i64=0 }
fn ty(self: Importer&,id: u32,depth: i64) -> u32,Error {
 if id<=5 { return id,Error.none; } if depth>=256 { return 0,Error.type_limit; }
 if self.scope_count==0 { let known=self.types.get(id); if known { return known,Error.none; } }
 let e=self.destination.chargeProjection(); if e!=Error.none { return 0,e; } let n=self.source.node(id); let tag=n.tag; var result: u32=0;
 if tag==Tag.scoped { let base,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; } let value,error=self.destination.scoped(base,blot_check_types::NominalIdentity {n.b,n.c}); if error!=Error.none { return 0,error; } result=value; }
 else if tag==Tag.erased_proof { let value,error=self.destination.proofKind(); if error!=Error.none { return 0,error; } result=value; }
 else if tag==Tag.projection {
  let descriptor=self.source.projection(id); if descriptor.scope>=self.scope_count { return 0,Error.type_mismatch; } var arguments: u32[>..<]=[];
  for arg in self.source.children(id) { let value,err=ty(self,arg,depth+1); if err!=Error.none { return 0,err; } arguments.push(value); }
  let value,error=self.destination.projection(blot_check_types::NominalIdentity {n.a,n.b},descriptor.member,arguments); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.bound {
  if n.c>=self.scope_count { return 0,Error.type_mismatch; } let frame=self.frames[self.scope_count-1-n.c]; if n.a>=frame.len { return 0,Error.type_mismatch; }
  result=self.binders[frame.start+n.a]; if self.destination.node(result).b!=n.b { return 0,Error.type_mismatch; }
 } else if tag==Tag.forall||tag==Tag.existential {
  if n.b==0||n.b>128||self.scope_count==128 { return 0,Error.type_limit; } let first=self.binders.len;
  for formal,ordinal in self.source.children(id) { let leaf=self.source.node(formal); if leaf.tag!=Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { return 0,Error.type_mismatch; } let value,err=self.destination.boundType(ordinal as u32,leaf.b); if err!=Error.none { return 0,err; } self.binders.push(value); }
  self.frames[self.scope_count]=Frame {first as u32,n.b}; self.scope_count++; defer { self.scope_count--; self.binders.resize(first); }
  var goals: blot_check_types::Obligation[>..<]=[];
  for goal in self.source.quantifierGoals(id) {
   let err=self.destination.chargeProjection(); if err!=Error.none { return 0,err; }
   var value=blot_check_types::Obligation {ty:0,kind:goal.kind,source:0,name:goal.name,operator:goal.operator,identity:goal.identity,explicit:goal.explicit};
   if goal.ty!=0 { let v,e1=ty(self,goal.ty,depth+1); if e1!=Error.none { return 0,e1; } value.ty=v; } if goal.other!=0 { let v,e2=ty(self,goal.other,depth+1); if e2!=Error.none { return 0,e2; } value.other=v; } if goal.result!=0 { let v,e3=ty(self,goal.result,depth+1); if e3!=Error.none { return 0,e3; } value.result=v; } if goal.signature!=0 { let v,e4=ty(self,goal.signature,depth+1); if e4!=Error.none { return 0,e4; } value.signature=v; } goals.push(value);
  }
  let body,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; } var result_tag=blot_check_types::Tag.existential; if tag==Tag.forall { result_tag=blot_check_types::Tag.forall; }
  let value,error=self.destination.quantifiedWithGoals(result_tag,body,self.binders[first..first+n.b],goals); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.usage {
  let base,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; } var region: u32=0; if n.c!=0 { let value,error=ty(self,n.c,depth+1); if error!=Error.none { return 0,error; } region=value; }
  let usage,known=blot_check_types::usageKindFromCode(n.b as u32); if !known { return 0,Error.type_mismatch; } let value,error=self.destination.usage(base,usage,region); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.function {
  let input,e1=ty(self,n.a,depth+1); if e1!=Error.none { return 0,e1; } let output,e2=ty(self,n.b,depth+1); if e2!=Error.none { return 0,e2; } let effects,e3=row(self,n.c,depth+1); if e3!=Error.none { return 0,e3; } let value,error=self.destination.functionWithEffects(input,output,effects); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider {
  let base,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; }
  if tag==Tag.resolver { let value,error=self.destination.resolver(base); if error!=Error.none { return 0,error; } result=value; }
  else if tag==Tag.provider { let effects,e=row(self,n.c,depth+1); if e!=Error.none { return 0,e; } let value,error=self.destination.provider(base,effects); if error!=Error.none { return 0,error; } result=value; }
  else { var sequence=blot_check_types::Tag.array; if tag==Tag.list { sequence=blot_check_types::Tag.list; } else if tag==Tag.cursor { sequence=blot_check_types::Tag.cursor; } let value,error=self.destination.sequence(sequence,base); if error!=Error.none { return 0,error; } result=value; }
 } else if tag==Tag.state_provider {
  let read,e1=ty(self,n.a,depth+1); if e1!=Error.none { return 0,e1; } let write,e2=ty(self,n.b,depth+1); if e2!=Error.none { return 0,e2; } let state,e3=ty(self,n.c,depth+1); if e3!=Error.none { return 0,e3; } let value,error=self.destination.stateProvider(read,write,state); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.type_constructor { let value,error=self.destination.typeConstructor(blot_check_types::NominalIdentity {n.a,n.b}); if error!=Error.none { return 0,error; } result=value; }
 else if tag==Tag.product||tag==Tag.nominal {
  var children: u32[>..<]=[]; for child in self.source.children(id) { let value,e=ty(self,child,depth+1); if e!=Error.none { return 0,e; } children.push(value); }
  if tag==Tag.nominal { let value,error=self.destination.nominal(blot_check_types::NominalIdentity {n.a,n.b},children); if error!=Error.none { return 0,error; } result=value; }
  else { let value,error=self.destination.product(children); if error!=Error.none { return 0,error; } result=value; }
 } else if tag==Tag.record {
  var fields: blot_check_types::Field[>..<]=[]; let children=self.source.children(id); var at=0;
  while at<children.len { let value,e=ty(self,children[at+1],depth+1); if e!=Error.none { return 0,e; } fields.push(blot_check_types::Field {children[at],value}); at+=2; } let value,error=self.destination.record(fields); if error!=Error.none { return 0,error; } result=value;
 } else { return 0,Error.type_mismatch; }
 if self.scope_count==0 { self.types.insert(id,result); } return result,Error.none;
}
fn row(self: Importer&,id: u32,depth: i64) -> u32,Error {
 if id==0 { return 0,Error.none; } if depth>=256 { return 0,Error.type_limit; } if self.scope_count==0 { let known=self.rows.get(id); if known { return known,Error.none; } }
 let e=self.destination.chargeProjection(); if e!=Error.none { return 0,e; } var labels: u32[>..<]=[];
 for label in self.source.effects.rowLabels(id) {
  let err=self.destination.chargeProjection(); if err!=Error.none { return 0,err; } let operation=self.source.effects.operation(label); var arguments: u32[>..<]=[];
  for argument in self.source.effects.operationArguments(label) { let value,error=ty(self,argument,depth+1); if error!=Error.none { return 0,error; } arguments.push(value); }
  let value,error=self.destination.internScopedOperation(operation.identity,operation.instance,arguments); if error!=Error.none { return 0,error; } labels.push(value);
 }
 var tail=blot_check_effects::Tail.closed; let formal=self.source.effects.rows[id].formal;
 if formal!=0 { let value,error=ty(self,formal,depth+1); if error!=Error.none { return 0,error; } tail=blot_check_effects::Tail.formal {value:value}; }
 let result,err=self.destination.effects.row(labels,tail); if err!=Error.none { return 0,blot_check_types::effectError(err); } if self.scope_count==0 { self.rows.insert(id,result); } return result,Error.none;
}
