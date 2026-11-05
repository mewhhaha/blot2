namespace blot_eval_closed_evidence_import;
import dictionary;
import .type_evidence;
import check.types;
import check.effects;
import support.error;
import support.native;
import .semantic_evidence_import;
import support.pooled_buffer;
type Error=blot_error::Error;
type Tag=blot_eval_type_evidence::Tag;
struct Frame { start: u32,len: u32 }
struct Importer { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View,destination: blot_check_types::Store,types: dictionary<u32,u32>&,rows: dictionary<u32,u32>&,binders: u32[>..<]&,frames: Frame[128],scope_count: i64=0 }
fn ty<I>(self: I&,id: u32,depth: i64) -> u32,Error { var arguments=Words {}; var goals=Goals {}; var children=Words {}; var fields=Fields {}; let value,error=tyInner(self,id,depth,arguments,goals,children,fields); arguments.deinit(); goals.deinit(); children.deinit(); fields.deinit(); return value,error; }
fn tyInner<I>(self: I&,id: u32,depth: i64,arguments: Words&,goals: Goals&,copied_children: Words&,field_values: Fields&) -> u32,Error {
 let destination=target(self);
 if id<=5 { return id,Error.none; } if depth>=256 { return 0,Error.type_limit; }
 if self.scope_count==0 { let known=self.types.get(id); if known { return known,Error.none; } }
 let e=destination.chargeProjection(); if e!=Error.none { return 0,e; } let n=self.source.node(id); let tag=n.tag; var result: u32=0;
 if tag==Tag.scoped { let base,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; } let value,error=destination.scoped(base,blot_check_types::NominalIdentity {n.b,n.c}); if error!=Error.none { return 0,error; } result=value; }
 else if tag==Tag.erased_proof { let value,error=destination.proofKind(); if error!=Error.none { return 0,error; } result=value; }
 else if tag==Tag.projection {
  let descriptor=self.source.projection(id); if descriptor.scope>=self.scope_count { return 0,Error.type_mismatch; } 
  for arg in self.source.children(id) { let value,err=ty(self,arg,depth+1); if err!=Error.none { return 0,err; } arguments.push(value); }
  if arguments.failure!=Error.none { return 0,arguments.failure; } let value,error=destination.projection(blot_check_types::NominalIdentity {n.a,n.b},descriptor.member,arguments.items); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.bound {
  if n.c>=self.scope_count { return 0,Error.type_mismatch; } let frame=self.frames[self.scope_count-1-n.c]; if n.a>=frame.len { return 0,Error.type_mismatch; }
  result=binderValues(self)[frame.start+n.a]; if destination.node(result).b!=n.b { return 0,Error.type_mismatch; }
 } else if tag==Tag.forall||tag==Tag.existential {
  if n.b==0||n.b>128||self.scope_count==128 { return 0,Error.type_limit; } let first=binderLength(self);
  for formal,ordinal in self.source.children(id) { let leaf=self.source.node(formal); if leaf.tag!=Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { return 0,Error.type_mismatch; } let value,err=destination.boundType(ordinal as u32,leaf.b); if err!=Error.none { return 0,err; } let pushed=pushBinder(self,value); if pushed!=Error.none { return 0,pushed; } }
  self.frames[self.scope_count]=Frame {first as u32,n.b}; self.scope_count++; 
  
  for goal in self.source.quantifierGoals(id) {
   let err=destination.chargeProjection(); if err!=Error.none { let __cleanup_result_142_0: u32 = 0; let __cleanup_result_142_1: Error = err; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_142_0, __cleanup_result_142_1; }
   var value=blot_check_types::Obligation {ty:0,kind:goal.kind,source:0,name:goal.name,operator:goal.operator,identity:goal.identity,explicit:goal.explicit};
   if goal.ty!=0 { let v,e1=ty(self,goal.ty,depth+1); if e1!=Error.none { let __cleanup_result_143_0: u32 = 0; let __cleanup_result_143_1: Error = e1; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_143_0, __cleanup_result_143_1; } value.ty=v; } if goal.other!=0 { let v,e2=ty(self,goal.other,depth+1); if e2!=Error.none { let __cleanup_result_144_0: u32 = 0; let __cleanup_result_144_1: Error = e2; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_144_0, __cleanup_result_144_1; } value.other=v; } if goal.result!=0 { let v,e3=ty(self,goal.result,depth+1); if e3!=Error.none { let __cleanup_result_145_0: u32 = 0; let __cleanup_result_145_1: Error = e3; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_145_0, __cleanup_result_145_1; } value.result=v; } if goal.signature!=0 { let v,e4=ty(self,goal.signature,depth+1); if e4!=Error.none { let __cleanup_result_146_0: u32 = 0; let __cleanup_result_146_1: Error = e4; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_146_0, __cleanup_result_146_1; } value.signature=v; } goals.push(value);
  }
  let body,err=ty(self,n.a,depth+1); if err!=Error.none { let __cleanup_result_147_0: u32 = 0; let __cleanup_result_147_1: Error = err; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_147_0, __cleanup_result_147_1; } var result_tag=blot_check_types::Tag.existential; if tag==Tag.forall { result_tag=blot_check_types::Tag.forall; }
  if goals.failure!=Error.none { self.scope_count--; resizeBinders(self,first); return 0,goals.failure; } let value,error=destination.quantifiedWithGoals(result_tag,body,binderValues(self)[first..first+n.b],goals.items); if error!=Error.none { let __cleanup_result_148_0: u32 = 0; let __cleanup_result_148_1: Error = error; { self.scope_count--; resizeBinders(self,first); } return __cleanup_result_148_0, __cleanup_result_148_1; } result=value;
  { self.scope_count--; resizeBinders(self,first); } } else if tag==Tag.usage {
  let base,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; } var region: u32=0; if n.c!=0 { let value,error=ty(self,n.c,depth+1); if error!=Error.none { return 0,error; } region=value; }
  let usage,known=blot_check_types::usageKindFromCode(n.b as u32); if !known { return 0,Error.type_mismatch; } let value,error=destination.usage(base,usage,region); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.function {
  let input,e1=ty(self,n.a,depth+1); if e1!=Error.none { return 0,e1; } let output,e2=ty(self,n.b,depth+1); if e2!=Error.none { return 0,e2; } let effects,e3=row(self,n.c,depth+1); if e3!=Error.none { return 0,e3; } let value,error=destination.functionWithEffects(input,output,effects); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider {
  let base,err=ty(self,n.a,depth+1); if err!=Error.none { return 0,err; }
  if tag==Tag.resolver { let value,error=destination.resolver(base); if error!=Error.none { return 0,error; } result=value; }
  else if tag==Tag.provider { let effects,e=row(self,n.c,depth+1); if e!=Error.none { return 0,e; } let value,error=destination.provider(base,effects); if error!=Error.none { return 0,error; } result=value; }
  else { var sequence=blot_check_types::Tag.array; if tag==Tag.list { sequence=blot_check_types::Tag.list; } else if tag==Tag.cursor { sequence=blot_check_types::Tag.cursor; } let value,error=destination.sequence(sequence,base); if error!=Error.none { return 0,error; } result=value; }
 } else if tag==Tag.state_provider {
  let read,e1=ty(self,n.a,depth+1); if e1!=Error.none { return 0,e1; } let write,e2=ty(self,n.b,depth+1); if e2!=Error.none { return 0,e2; } let state,e3=ty(self,n.c,depth+1); if e3!=Error.none { return 0,e3; } let value,error=destination.stateProvider(read,write,state); if error!=Error.none { return 0,error; } result=value;
 } else if tag==Tag.type_constructor { let value,error=destination.typeConstructor(blot_check_types::NominalIdentity {n.a,n.b}); if error!=Error.none { return 0,error; } result=value; }
 else if tag==Tag.product||tag==Tag.nominal {
   for child in self.source.children(id) { let value,e=ty(self,child,depth+1); if e!=Error.none { return 0,e; } copied_children.push(value); }
  if copied_children.failure!=Error.none { return 0,copied_children.failure; } if tag==Tag.nominal { let value,error=destination.nominal(blot_check_types::NominalIdentity {n.a,n.b},copied_children.items); if error!=Error.none { return 0,error; } result=value; }
  else { let value,error=destination.product(copied_children.items); if error!=Error.none { return 0,error; } result=value; }
 } else if tag==Tag.record {
   let children=self.source.children(id); var at=0;
  while at<children.len { let value,e=ty(self,children[at+1],depth+1); if e!=Error.none { return 0,e; } field_values.push(blot_check_types::Field {children[at],value}); at+=2; } if field_values.failure!=Error.none { return 0,field_values.failure; } let value,error=destination.record(field_values.items); if error!=Error.none { return 0,error; } result=value;
 } else { return 0,Error.type_mismatch; }
 if self.scope_count==0 { self.types.insert(id,result); } return result,Error.none;
}
fn row<I>(self: I&,id: u32,depth: i64) -> u32,Error { var labels=Words {}; var arguments=Words {}; let value,error=rowInner(self,id,depth,labels,arguments); labels.deinit(); arguments.deinit(); return value,error; }
fn rowInner<I>(self: I&,id: u32,depth: i64,labels: Words&,arguments: Words&) -> u32,Error {
 let destination=target(self);
 if id==0 { return 0,Error.none; } if depth>=256 { return 0,Error.type_limit; } if self.scope_count==0 { let known=self.rows.get(id); if known { return known,Error.none; } }
 let e=destination.chargeProjection(); if e!=Error.none { return 0,e; } 
 for label in self.source.effects.rowLabels(id) { arguments.items=arguments.storage[..0];
  let err=destination.chargeProjection(); if err!=Error.none { return 0,err; } let operation=self.source.effects.operation(label); 
  for argument in self.source.effects.operationArguments(label) { let value,error=ty(self,argument,depth+1); if error!=Error.none { return 0,error; } arguments.push(value); }
  if arguments.failure!=Error.none { return 0,arguments.failure; } let value,error=destination.internScopedOperation(operation.identity,operation.instance,arguments.items); if error!=Error.none { return 0,error; } labels.push(value);
 }
 if labels.failure!=Error.none { return 0,labels.failure; } var tail=blot_check_effects::Tail.closed; let formal=self.source.effects.rows[id].formal;
 if formal!=0 { let value,error=ty(self,formal,depth+1); if error!=Error.none { return 0,error; } tail=blot_check_effects::Tail.formal {value:value}; }
 let result,err=destination.effects.row(labels.items,tail); if err!=Error.none { return 0,blot_check_types::effectError(err); } if self.scope_count==0 { self.rows.insert(id,result); } return result,Error.none;
}

type Words=blot_eval_semantic_evidence_import::WordBuffer;
type WordMap=blot_eval_semantic_evidence_import::WordMap;
struct Goals { storage: blot_check_types::Obligation[:]=[],items: blot_check_types::Obligation[:]=[],failure: Error=Error.none }
struct Fields { storage: blot_check_types::Field[:]=[],items: blot_check_types::Field[:]=[],failure: Error=Error.none }
reusable[] var goal_runs: blot_check_types::Obligation[>..]=[];
reusable[] var field_runs: blot_check_types::Field[>..]=[];
fn push(self: Goals&,value: blot_check_types::Obligation) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,goal_runs); }
fn push(self: Fields&,value: blot_check_types::Field) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,field_runs); }
fn deinit(self: Goals&) { blot_support_pooled_buffer::deinit(self,goal_runs); }
fn deinit(self: Fields&) { blot_support_pooled_buffer::deinit(self,field_runs); }
struct PooledImporter { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View=blot_eval_type_evidence::View {nodes:[],extra:[],effects:blot_check_effect_evidence::View {}},destination: blot_check_types::Store=blot_check_types::Store {},types: WordMap=WordMap {},rows: WordMap=WordMap {},binders: Words=Words {},frames: Frame[128]=[Frame {0,0};128],scope_count: i64=0 }
fn initPooled(source: blot_eval_type_evidence::View,destination: blot_check_types::Store&) -> PooledImporter { return PooledImporter {source:source,destination:destination}; }
fn deinit(self: PooledImporter&) { self.types.deinit(); self.rows.deinit(); self.binders.deinit(); self.destination=Store {}; self.scope_count=0; self.owner_id=0; }
fn deinit(self: Importer&) { self.types.clear(); self.rows.clear(); self.binders.clear(); self.scope_count=0; self.owner_id=0; }
fn target(self: Importer&) -> blot_check_types::Store { return self.destination; }
fn target(self: PooledImporter&) -> blot_check_types::Store { if self.destination.owner_id==0 { abort("inactive closed evidence importer"); } return self.destination; }
fn binderLength(self: Importer&) -> i64 { return self.binders.len; }
fn binderLength(self: PooledImporter&) -> i64 { return self.binders.items.len; }
fn binderValues(self: Importer&) -> const u32[:] { return self.binders; }
fn binderValues(self: PooledImporter&) -> const u32[:] { return self.binders.items; }
fn pushBinder(self: Importer&,value: u32) -> Error { self.binders.push(value); return Error.none; }
fn pushBinder(self: PooledImporter&,value: u32) -> Error { self.binders.push(value); return self.binders.failure; }
fn resizeBinders(self: Importer&,length: i64) { self.binders.resize(length); }
fn resizeBinders(self: PooledImporter&,length: i64) { assert(length>=0&&length<=self.binders.items.len); self.binders.items=self.binders.storage[..length]; }
fn withImporter<C,F,R>(source: blot_eval_type_evidence::View,destination: blot_check_types::Store,context: C&) -> R,Error { var importer=initPooled(source,destination); let result,error=F(context,importer); importer.deinit(); return result,error; }
