namespace blot_eval_semantic_evidence_import;
import dictionary;
import .type_evidence;
import check.types;
import support.error;
import support.native;
import support.pooled_map;
import support.pooled_buffer;
type Error=blot_error::Error;
type Tag=blot_eval_type_evidence::Tag;
struct Importer { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View,destination: blot_eval_type_evidence::Store&,max_depth: i64,allow_scoped: bool=true,remaining: i64?=null,nodes: dictionary<u32,u32>&,rows: dictionary<u32,u32>&,labels: dictionary<u32,u32>& }
fn charge<I>(self: I&) -> Error { if self.remaining!=null { if self.remaining==0 { return Error.evidence_limit; } self.remaining--; } return Error.none; }
fn ty<I>(self: I&,id: u32,depth: i64) -> u32,Error { var copied=WordBuffer {}; var goals=GoalBuffer {}; let value,error=tyInner(self,id,depth,copied,goals); deinit(copied); deinit(goals); return value,error; }
fn tyInner<I>(self: I&,id: u32,depth: i64,copied: WordBuffer&,goals: GoalBuffer&) -> u32,Error {
 let destination: blot_eval_type_evidence::Store&=target(self);
 if id==0 { return 0,Error.none; } if depth>=self.max_depth||id>=self.source.nodes.len { return 0,Error.evidence_limit; } if id<=5 { return id,Error.none; } let known=self.nodes.get(id); if known { return known,Error.none; }
 let error=charge(self); if error!=Error.none { return 0,error; } let n=self.source.node(id); let tag=n.tag;
 if !self.allow_scoped&&(tag==Tag.scoped||(tag==Tag.usage&&n.c!=0)) { return 0,Error.type_mismatch; }
  for child,index in self.source.children(id) { if tag==Tag.record&&index%2==0 { copied.push(child); } else { let value,e=ty(self,child,depth+1); if e!=Error.none { return 0,e; } copied.push(value); } }
 if copied.failure!=Error.none { return 0,copied.failure; } var a: u32=0; var b: u32=0; var c: u32=0;
 if tag==Tag.usage||tag==Tag.scoped||tag==Tag.forall||tag==Tag.existential||tag==Tag.function||tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider||tag==Tag.state_provider { let value,e=ty(self,n.a,depth+1); if e!=Error.none { return 0,e; } a=value; }
 else if tag==Tag.bound||tag==Tag.nominal||tag==Tag.type_constructor { a=n.a; }
 if tag==Tag.function||tag==Tag.state_provider { let value,e=ty(self,n.b,depth+1); if e!=Error.none { return 0,e; } b=value; }
 else if tag==Tag.bound||tag==Tag.usage||tag==Tag.scoped||tag==Tag.forall||tag==Tag.existential||tag==Tag.nominal||tag==Tag.type_constructor { b=n.b; }
 if tag==Tag.function||tag==Tag.provider { let value,e=row(self,n.c,depth+1); if e!=Error.none { return 0,e; } c=value; }
 else if tag==Tag.state_provider||(tag==Tag.usage&&n.c!=0) { let value,e=ty(self,n.c,depth+1); if e!=Error.none { return 0,e; } c=value; }
 else if tag==Tag.bound||tag==Tag.scoped { c=n.c; }
 var result: u32=0;
 if tag==Tag.projection { let p=self.source.projection(id); let value,e=destination.internProjection(blot_check_types::NominalIdentity {n.a,n.b},p.member,copied.items,p.scope,p.goal); if e!=Error.none { return 0,e; } result=value; }
 else if tag==Tag.forall||tag==Tag.existential {
  
  for goal in self.source.quantifierGoals(id) {
   let e=charge(self); if e!=Error.none { return 0,e; } var value=goal;
   let t,e1=ty(self,goal.ty,depth+1); if e1!=Error.none { return 0,e1; } value.ty=t;
   let other,e2=ty(self,goal.other,depth+1); if e2!=Error.none { return 0,e2; } value.other=other;
   let output,e3=ty(self,goal.result,depth+1); if e3!=Error.none { return 0,e3; } value.result=output;
   let signature,e4=ty(self,goal.signature,depth+1); if e4!=Error.none { return 0,e4; } value.signature=signature; goals.push(value);
  }
  if goals.failure!=Error.none { return 0,goals.failure; } let value,e=destination.internQuantifiedWithGoals(tag,a,copied.items,goals.items); if e!=Error.none { return 0,e; } result=value;
 } else if tag==Tag.state_provider { let value,e=destination.internStateProvider(a,b,c); if e!=Error.none { return 0,e; } result=value; }
 else { let value,e=destination.internWithEffects(tag,a,b,c,copied.items); if e!=Error.none { return 0,e; } result=value; }
 self.nodes.insert(id,result); return result,Error.none;
}
fn row<I>(self: I&,id: u32,depth: i64) -> u32,Error { var copied=WordBuffer {}; let value,error=rowInner(self,id,depth,copied); deinit(copied); return value,error; }
fn rowInner<I>(self: I&,id: u32,depth: i64,copied: WordBuffer&) -> u32,Error {
 let destination: blot_eval_type_evidence::Store&=target(self);
 if id==0 { return 0,Error.none; } if depth>=self.max_depth||id>=self.source.effects.rows.len { return 0,Error.evidence_limit; } let known=self.rows.get(id); if known { return known,Error.none; }
 let err=charge(self); if err!=Error.none { return 0,err; } 
 for old in self.source.effects.rowLabels(id) { let value,e=label(self,old,depth+1); if e!=Error.none { return 0,e; } copied.push(value); }
 if copied.failure!=Error.none { return 0,copied.failure; } let old_formal=self.source.effects.rows[id].formal; var formal: u32=0; if old_formal!=0 { let value,e=ty(self,old_formal,depth+1); if e!=Error.none { return 0,e; } formal=value; }
 let result,error=destination.effects.internRowWithFormal(copied.items,formal); if error!=Error.none { return 0,error; } self.rows.insert(id,result); return result,Error.none;
}
fn label<I>(self: I&,id: u32,depth: i64) -> u32,Error { var copied=WordBuffer {}; let value,error=labelInner(self,id,depth,copied); deinit(copied); return value,error; }
fn labelInner<I>(self: I&,id: u32,depth: i64,copied: WordBuffer&) -> u32,Error {
 let destination: blot_eval_type_evidence::Store&=target(self);
 if depth>=self.max_depth||id==0||id>=self.source.effects.operations.len { return 0,Error.evidence_limit; } let known=self.labels.get(id); if known { return known,Error.none; }
 let err=charge(self); if err!=Error.none { return 0,err; } let operation=self.source.effects.operation(id);
 if !self.allow_scoped&&(operation.instance.unit!=0||operation.instance.decl!=0) { return 0,Error.type_mismatch; }
  for old in self.source.effects.operationArguments(id) { let value,e=ty(self,old,depth+1); if e!=Error.none { return 0,e; } copied.push(value); }
 if copied.failure!=Error.none { return 0,copied.failure; } let result,error=destination.effects.internOperationInstance(operation.identity,copied.items,operation.instance); if error!=Error.none { return 0,error; } self.labels.insert(id,result); return result,Error.none;
}

struct WordMap { table: blot_support_pooled_map::Map<u32,u32>=blot_support_pooled_map::Map<u32,u32> {} }
reusable[] var word_map_slots: dictionary_slot<u32,u32>[>..]=[];
fn get(self: WordMap&,key: u32) -> u32? { return blot_support_pooled_map::get(self.table,key); }
fn insert(self: WordMap&,key: u32,value: u32) { blot_support_pooled_map::insert(self.table,key,value,word_map_slots); }
fn clear(self: WordMap&) { blot_support_pooled_map::clear(self.table); }
fn deinit(self: WordMap&) { blot_support_pooled_map::deinit(self.table,word_map_slots); }
struct PooledImporter { owner_id: u64=blot_native::fresh_owner_id(),source: blot_eval_type_evidence::View=blot_eval_type_evidence::View {nodes:[],extra:[],effects:blot_check_effect_evidence::View {}},destination: blot_eval_type_evidence::Store?=null,max_depth: i64=0,allow_scoped: bool=true,remaining: i64?=null,nodes: WordMap=WordMap {},rows: WordMap=WordMap {},labels: WordMap=WordMap {} }
fn initPooled(source: blot_eval_type_evidence::View,destination: blot_eval_type_evidence::Store&,max_depth: i64,allow_scoped: bool) -> PooledImporter { return PooledImporter {source:source,destination:destination,max_depth:max_depth,allow_scoped:allow_scoped}; }
fn deinit(self: PooledImporter&) { self.nodes.deinit(); self.rows.deinit(); self.labels.deinit(); self.destination .= null; self.remaining .= null; self.owner_id=0; }
fn target(self: Importer&) -> blot_eval_type_evidence::Store& { return self.destination; }
fn target(self: PooledImporter&) -> blot_eval_type_evidence::Store& { if self.destination==null { abort("inactive semantic evidence importer"); } return self.destination; }
struct WordBuffer { storage: u32[:]=[],items: u32[:]=[],failure: Error=Error.none }
struct GoalBuffer { storage: blot_eval_type_evidence::Goal[:]=[],items: blot_eval_type_evidence::Goal[:]=[],failure: Error=Error.none }
reusable[] var copied_words: u32[>..]=[];
reusable[] var copied_goals: blot_eval_type_evidence::Goal[>..]=[];
fn push(self: WordBuffer&,value: u32) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,copied_words); }
fn push(self: GoalBuffer&,value: blot_eval_type_evidence::Goal) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,copied_goals); }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self,copied_words); }
fn deinit(self: GoalBuffer&) { blot_support_pooled_buffer::deinit(self,copied_goals); }
