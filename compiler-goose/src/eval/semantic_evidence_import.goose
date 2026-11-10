namespace blot_eval_semantic_evidence_import;
import check.effect_evidence;
import check.types;
import eval.type_evidence;
import support.error;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

import dictionary;
type Error=blot_error::Error;
type Tag=blot_eval_type_evidence::Tag;
struct Importer { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View,destination: blot_eval_type_evidence::Store,max_depth: i64,allow_scoped: bool=true,remaining: i64?=null,nodes: dictionary<u32,u32>&,rows: dictionary<u32,u32>&,labels: dictionary<u32,u32>& }
fn charge<I>(self_: I&) -> Error { let remaining=self_.remaining; if remaining!=null { if remaining==0 { return blot_error::Error.evidence_limit; } remaining--; } return blot_error::Error.none; }
recursive fn ty<I>(self_: I&,id: u32,depth: i64) -> u32,Error { var copied=WordBuffer {}; var goals=GoalBuffer {}; let value,error=tyInner(self_,id,depth,copied,goals); deinit(copied); deinit(goals); return value,error; }
recursive fn tyInner<I>(self_: I&,id: u32,depth: i64,copied: WordBuffer&,goals: GoalBuffer&) -> u32,Error {
 let destination=target(self_);
 if id==0 { return 0,blot_error::Error.none; } if depth>=self_.max_depth||id>=self_.source.nodes.len { return 0,blot_error::Error.evidence_limit; } if id<=5 { return id,blot_error::Error.none; } let known=self_.nodes.get(id); if known { return known,blot_error::Error.none; }
 let error=charge(self_); if error!=blot_error::Error.none { return 0,error; } let n=self_.source.node(id); let tag=n.tag;
 if !self_.allow_scoped&&(tag==blot_eval_type_evidence::Tag.scoped||(tag==blot_eval_type_evidence::Tag.usage&&n.c!=0)) { return 0,blot_error::Error.type_mismatch; }
  for child,index in self_.source.children(id) { if tag==blot_eval_type_evidence::Tag.record&&index%2==0 { copied.push(child); } else { let value,e=ty(self_,child,depth+1); if e!=blot_error::Error.none { return 0,e; } copied.push(value); } }
 if copied.failure!=blot_error::Error.none { return 0,copied.failure; } var a: u32=0; var b: u32=0; var c: u32=0;
 if tag==blot_eval_type_evidence::Tag.usage||tag==blot_eval_type_evidence::Tag.scoped||tag==blot_eval_type_evidence::Tag.forall||tag==blot_eval_type_evidence::Tag.existential||tag==blot_eval_type_evidence::Tag.function||tag==blot_eval_type_evidence::Tag.array||tag==blot_eval_type_evidence::Tag.list||tag==blot_eval_type_evidence::Tag.cursor||tag==blot_eval_type_evidence::Tag.resolver||tag==blot_eval_type_evidence::Tag.provider||tag==blot_eval_type_evidence::Tag.state_provider { let value,e=ty(self_,n.a,depth+1); if e!=blot_error::Error.none { return 0,e; } a=value; }
 else if tag==blot_eval_type_evidence::Tag.bound||tag==blot_eval_type_evidence::Tag.nominal||tag==blot_eval_type_evidence::Tag.type_constructor { a=n.a; }
 if tag==blot_eval_type_evidence::Tag.function||tag==blot_eval_type_evidence::Tag.state_provider { let value,e=ty(self_,n.b,depth+1); if e!=blot_error::Error.none { return 0,e; } b=value; }
 else if tag==blot_eval_type_evidence::Tag.bound||tag==blot_eval_type_evidence::Tag.usage||tag==blot_eval_type_evidence::Tag.scoped||tag==blot_eval_type_evidence::Tag.forall||tag==blot_eval_type_evidence::Tag.existential||tag==blot_eval_type_evidence::Tag.nominal||tag==blot_eval_type_evidence::Tag.type_constructor { b=n.b; }
 if tag==blot_eval_type_evidence::Tag.function||tag==blot_eval_type_evidence::Tag.provider { let value,e=row(self_,n.c,depth+1); if e!=blot_error::Error.none { return 0,e; } c=value; }
 else if tag==blot_eval_type_evidence::Tag.state_provider||(tag==blot_eval_type_evidence::Tag.usage&&n.c!=0) { let value,e=ty(self_,n.c,depth+1); if e!=blot_error::Error.none { return 0,e; } c=value; }
 else if tag==blot_eval_type_evidence::Tag.bound||tag==blot_eval_type_evidence::Tag.scoped { c=n.c; }
 var result: u32=0;
 if tag==blot_eval_type_evidence::Tag.projection { let p=self_.source.projection(id); let value,e=destination.internProjection(blot_check_types::NominalIdentity {n.a,n.b},p.member,copied.items,p.scope,p.goal); if e!=blot_error::Error.none { return 0,e; } result=value; }
 else if tag==blot_eval_type_evidence::Tag.forall||tag==blot_eval_type_evidence::Tag.existential {

  for goal in self_.source.quantifierGoals(id) {
   let e=charge(self_); if e!=blot_error::Error.none { return 0,e; } var value=goal;
   let t,e1=ty(self_,goal.ty,depth+1); if e1!=blot_error::Error.none { return 0,e1; } value.ty=t;
   let other,e2=ty(self_,goal.other,depth+1); if e2!=blot_error::Error.none { return 0,e2; } value.other=other;
   let output,e3=ty(self_,goal.result,depth+1); if e3!=blot_error::Error.none { return 0,e3; } value.result=output;
   let signature,e4=ty(self_,goal.signature,depth+1); if e4!=blot_error::Error.none { return 0,e4; } value.signature=signature; goals.push(value);
  }
  if goals.failure!=blot_error::Error.none { return 0,goals.failure; } let value,e=destination.internQuantifiedWithGoals(tag,a,copied.items,goals.items); if e!=blot_error::Error.none { return 0,e; } result=value;
 } else if tag==blot_eval_type_evidence::Tag.state_provider { let value,e=destination.internStateProvider(a,b,c); if e!=blot_error::Error.none { return 0,e; } result=value; }
 else { let value,e=destination.internWithEffects(tag,a,b,c,copied.items); if e!=blot_error::Error.none { return 0,e; } result=value; }
 self_.nodes.insert(id,result); return result,blot_error::Error.none;
}
recursive fn row<I>(self_: I&,id: u32,depth: i64) -> u32,Error { var copied=WordBuffer {}; let value,error=rowInner(self_,id,depth,copied); deinit(copied); return value,error; }
recursive fn rowInner<I>(self_: I&,id: u32,depth: i64,copied: WordBuffer&) -> u32,Error {
 let destination=target(self_);
 if id==0 { return 0,blot_error::Error.none; } if depth>=self_.max_depth||id>=self_.source.effects.rows.len { return 0,blot_error::Error.evidence_limit; } let known=self_.rows.get(id); if known { return known,blot_error::Error.none; }
 let err=charge(self_); if err!=blot_error::Error.none { return 0,err; }
 for old in self_.source.effects.rowLabels(id) { let value,e=label(self_,old,depth+1); if e!=blot_error::Error.none { return 0,e; } copied.push(value); }
 if copied.failure!=blot_error::Error.none { return 0,copied.failure; } let old_formal=self_.source.effects.rows[id].formal; var formal: u32=0; if old_formal!=0 { let value,e=ty(self_,old_formal,depth+1); if e!=blot_error::Error.none { return 0,e; } formal=value; }
 let result,error=destination.effects.internRowWithFormal(copied.items,formal); if error!=blot_error::Error.none { return 0,error; } self_.rows.insert(id,result); return result,blot_error::Error.none;
}
recursive fn label<I>(self_: I&,id: u32,depth: i64) -> u32,Error { var copied=WordBuffer {}; let value,error=labelInner(self_,id,depth,copied); deinit(copied); return value,error; }
recursive fn labelInner<I>(self_: I&,id: u32,depth: i64,copied: WordBuffer&) -> u32,Error {
 let destination=target(self_);
 if depth>=self_.max_depth||id==0||id>=self_.source.effects.operations.len { return 0,blot_error::Error.evidence_limit; } let known=self_.labels.get(id); if known { return known,blot_error::Error.none; }
 let err=charge(self_); if err!=blot_error::Error.none { return 0,err; } let operation=self_.source.effects.operation(id);
 if !self_.allow_scoped&&(operation.instance.unit!=0||operation.instance.decl!=0) { return 0,blot_error::Error.type_mismatch; }
  for old in self_.source.effects.operationArguments(id) { let value,e=ty(self_,old,depth+1); if e!=blot_error::Error.none { return 0,e; } copied.push(value); }
 if copied.failure!=blot_error::Error.none { return 0,copied.failure; } let result,error=destination.effects.internOperationInstance(operation.identity,copied.items,operation.instance); if error!=blot_error::Error.none { return 0,error; } self_.labels.insert(id,result); return result,blot_error::Error.none;
}

struct WordMap { table: blot_support_pooled_map::Map<u32,u32> =blot_support_pooled_map::Map<u32,u32> {} }
reusable[] var word_map_slots: dictionary_slot<u32,u32>[>..]=[];
fn get(self_: WordMap&,key: u32) -> u32? { return blot_support_pooled_map::get(self_.table,key); }
fn insert(self_: WordMap&,key: u32,value: u32) { blot_support_pooled_map::insert(self_.table,key,value,word_map_slots); }
fn clear(self_: WordMap&) { blot_support_pooled_map::clear(self_.table); }
fn deinit(self_: WordMap&) { blot_support_pooled_map::deinit(self_.table,word_map_slots); }
struct PooledImporter { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View=blot_eval_type_evidence::View {nodes:default<const blot_eval_type_evidence::Node[:]>(),extra:default<const u32[:]>(),effects:blot_check_effect_evidence::View {}},destination: blot_eval_type_evidence::Store=blot_eval_type_evidence::Store {},max_depth: i64=0,allow_scoped: bool=true,remaining: i64?=null,nodes: WordMap=WordMap {},rows: WordMap=WordMap {},labels: WordMap=WordMap {} }
fn initPooled(source: blot_eval_type_evidence::View,destination: blot_eval_type_evidence::Store,max_depth: i64,allow_scoped: bool) -> PooledImporter { return PooledImporter {source:source,destination:destination,max_depth:max_depth,allow_scoped:allow_scoped}; }
fn deinit(self_: PooledImporter&) { self_.nodes.deinit(); self_.rows.deinit(); self_.labels.deinit(); self_.destination=blot_eval_type_evidence::Store {}; self_.remaining .= null; self_.owner_id=0; }
// The enclosing artifact Importer fixes the source domain until reset. Keep
// only memo state here; each operation borrows its source for that call.
struct RetainedImporter { owner_id:u64=blot_native::fresh_owner_id(),destination:blot_eval_type_evidence::Handle=default<blot_eval_type_evidence::Handle>(),max_depth:i64=0,allow_scoped:bool=true,nodes:WordMap=WordMap{},rows:WordMap=WordMap{},labels:WordMap=WordMap{} }
struct RetainedReader { owner_id:u64,source:blot_eval_type_evidence::View,destination:blot_eval_type_evidence::Store,max_depth:i64,allow_scoped:bool,remaining:i64?,nodes:WordMap&,rows:WordMap&,labels:WordMap& }
fn initRetained(destination:blot_eval_type_evidence::Store,max_depth:i64,allow_scoped:bool)->RetainedImporter { return RetainedImporter{destination:blot_eval_type_evidence::acquireHandle(destination),max_depth:max_depth,allow_scoped:allow_scoped}; }
fn tyWithSource(self_:RetainedImporter&,source:blot_eval_type_evidence::View,id:u32,depth:i64)->u32,Error { var reader=RetainedReader{owner_id:self_.owner_id,source:source,destination:blot_eval_type_evidence::reifyStore(self_.destination),max_depth:self_.max_depth,allow_scoped:self_.allow_scoped,remaining:null,nodes:self_.nodes,rows:self_.rows,labels:self_.labels}; return ty(reader,id,depth); }
fn deinit(self_:RetainedImporter&) { self_.nodes.deinit(); self_.rows.deinit(); self_.labels.deinit(); self_.destination=default<blot_eval_type_evidence::Handle>(); self_.owner_id=0; }
fn target(self_:RetainedReader&)->blot_eval_type_evidence::Store { if self_.destination.owner_id==0 {abort("inactive semantic evidence importer");} return self_.destination; }
fn target(self_: Importer&) -> blot_eval_type_evidence::Store { return self_.destination; }
fn target(self_: PooledImporter&) -> blot_eval_type_evidence::Store { if self_.destination.owner_id==0 { abort("inactive semantic evidence importer"); } return self_.destination; }
struct WordBuffer { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),failure: Error=blot_error::Error.none }
struct GoalBuffer { storage: blot_eval_type_evidence::Goal[:]=default<blot_eval_type_evidence::Goal[:]>(),items: blot_eval_type_evidence::Goal[:]=default<blot_eval_type_evidence::Goal[:]>(),failure: Error=blot_error::Error.none }
reusable[] var copied_words: u32[>..]=[];
reusable[] var copied_goals: blot_eval_type_evidence::Goal[>..]=[];
fn push(self_: WordBuffer&,value: u32) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,copied_words); }
fn push(self_: GoalBuffer&,value: blot_eval_type_evidence::Goal) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,copied_goals); }
fn deinit(self_: WordBuffer&) { blot_support_pooled_buffer::deinit(self_,copied_words); }
fn deinit(self_: GoalBuffer&) { blot_support_pooled_buffer::deinit(self_,copied_goals); }

fn get(self_:const dictionary<u32,u32>&,key:u32)->u32? {return ::get(self_,key);}
fn insert(self_:dictionary<u32,u32>&,key:u32,value:u32) {::insert(self_,key,value);}
