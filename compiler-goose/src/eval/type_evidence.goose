// Interned semantic types. Exact owner-local evidence; never a machine layout.
namespace blot_eval_type_evidence;
import eval.type_evidence_schema;
import check.effect_evidence;
import check.effects;
import check.types;
import eval.evidence_projection;
import parse.symbols;
import reuse.projection_cache;
import support.error;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

import dictionary;
import support.option;
type Id=u32;
type Error=blot_error::Error;
type Identity=blot_check_types::NominalIdentity;
fn tagFromCode(code: u8) -> Tag,bool {
 if code==0 { return Tag.absent,true; } if code==1 { return Tag.unit,true; } if code==2 { return Tag.boolean,true; } if code==3 { return Tag.unsigned32,true; } if code==4 { return Tag.floating32,true; } if code==5 { return Tag.never,true; } if code==6 { return Tag.function,true; } if code==7 { return Tag.product,true; } if code==8 { return Tag.record,true; } if code==9 { return Tag.nominal,true; } if code==10 { return Tag.array,true; } if code==11 { return Tag.list,true; } if code==12 { return Tag.cursor,true; } if code==13 { return Tag.type_constructor,true; } if code==14 { return Tag.resolver,true; } if code==15 { return Tag.provider,true; } if code==16 { return Tag.state_provider,true; } if code==17 { return Tag.erased_proof,true; } if code==20 { return Tag.bound,true; } if code==21 { return Tag.usage,true; } if code==23 { return Tag.scoped,true; } if code==24 { return Tag.forall,true; } if code==25 { return Tag.existential,true; } if code==26 { return Tag.projection,true; } return Tag.absent,false;
}
struct Mapping { variable: u32,evidence: Id }
struct RowMapping { variable: u32,evidence: u32 }
struct Goal { ty: Id,kind: blot_check_types::ObligationKind,name: u32=0,result: Id=0,other: Id=0,signature: Id=0,operator: blot_check_types::Operator=blot_check_types::Operator.none,identity: Identity=Identity {0,0},explicit: bool=false }
struct QuantifierGoals { owner: Id,goals: blot_check_types::List }
struct Projection { member: u32,scope: u32,goal: u32 }
struct ScopeFrame { binders: const Id[:],goals: const Goal[:]=default<const Goal[:]>() }
fn setScopeFrame(frames: ScopeFrame[:],index: i64,binders: const Id[:],goals: const Goal[:]) { frames[index]=ScopeFrame {binders,goals}; }
struct ProjectionResolver<R> { context: R,remaining: i64&,enabled: bool=true }
struct NoResolver {}
fn resolve(self_: NoResolver&,identity: Identity,member: u32,arguments: const Id[:]) -> Id,Error { return 0,blot_error::Error.unresolved_type; }
struct View { owner_id: u64=0,nodes: const Node[:],extra: const Id[:],effects: blot_check_effect_evidence::View,quantifier_goals: const QuantifierGoals[:]=default<const QuantifierGoals[:]>(),quantifier_obligations: const Goal[:]=default<const Goal[:]>() }
fn quantifierGoals(self_: View,owner: Id) -> const Goal[:] {
 var lo=0; var hi=self_.quantifier_goals.len;
 while lo<hi { let mid=lo+(hi-lo)/2; if self_.quantifier_goals[mid].owner<owner { lo=mid+1; } else { hi=mid; } }
 if lo<self_.quantifier_goals.len { let entry=self_.quantifier_goals[lo]; if entry.owner==owner { return self_.quantifier_obligations[entry.goals.start..entry.goals.start+entry.goals.len]; } } return self_.quantifier_obligations[..0];
}
fn validateGoalTables(self_: View) -> Error { var remaining: i64=65536; return validateGoalTablesWithBudget(self_,remaining); }
fn validateGoalTablesWithBudget(self_: View,remaining: i64&) -> Error {
 if self_.quantifier_goals.len>self_.nodes.len||self_.quantifier_obligations.len>65536 { return blot_error::Error.evidence_limit; }
 var previous: Id=0; var cursor=0;
 for entry in self_.quantifier_goals {
  if remaining==0 { return blot_error::Error.evidence_limit; } remaining--;
  if entry.owner<=previous||entry.owner>=self_.nodes.len||entry.goals.len==0||entry.goals.start!=cursor||cursor>self_.quantifier_obligations.len||entry.goals.len>self_.quantifier_obligations.len-cursor { return blot_error::Error.type_mismatch; }
  let tag=self_.node(entry.owner).tag; if tag!=Tag.forall&&tag!=Tag.existential { return blot_error::Error.type_mismatch; }
  for goal in self_.quantifier_obligations[entry.goals.start..entry.goals.start+entry.goals.len] {
   if remaining==0 { return blot_error::Error.evidence_limit; } remaining--;
   if blot_check_types::obligationKindCode(goal.kind)>blot_check_types::obligationKindCode(blot_check_types::ObligationKind.task_receive)||blot_check_types::operatorCode(goal.operator)>blot_check_types::operatorCode(blot_check_types::Operator.shift_right)||goal.ty==0 { return blot_error::Error.type_mismatch; }
   if goal.ty>=entry.owner||goal.other>=entry.owner||goal.result>=entry.owner||goal.signature>=entry.owner { return blot_error::Error.type_mismatch; }
  }
  previous=entry.owner; cursor+=entry.goals.len;
 }
 if cursor!=self_.quantifier_obligations.len { return blot_error::Error.type_mismatch; } return blot_error::Error.none;
}
fn node(self_: View,id: Id) -> Node { return self_.nodes[id]; }
fn children(self_: View,id: Id) -> const Id[:] {
 let n=node(self_,id);
 if n.tag==Tag.product { return self_.extra[n.a..n.a+n.b]; }
 if n.tag==Tag.record { return self_.extra[n.a..n.a+(n.b as i64)*2]; }
 if n.tag==Tag.nominal||n.tag==Tag.projection { return self_.extra[n.c+1..n.c+1+self_.extra[n.c]]; }
 if n.tag==Tag.forall||n.tag==Tag.existential { return self_.extra[n.c..n.c+n.b]; }
 return self_.extra[..0];
}
fn projection(self_: View,id: Id) -> Projection { let n=node(self_,id); let start=n.c+1+self_.extra[n.c]; return Projection {self_.extra[start],self_.extra[start+1],self_.extra[start+2]}; }
fn binderList(self_: View,binders: const Id[:],seen: bool[:],remaining: i64&) -> Error {
 if binders.len==0||binders.len>128 { return blot_error::Error.type_mismatch; }
 for id,ordinal in binders {
  if remaining==0 { return blot_error::Error.evidence_limit; } remaining--; if id==0||id>=self_.nodes.len { return blot_error::Error.type_mismatch; }
  let leaf=node(self_,id); if leaf.tag!=Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { return blot_error::Error.type_mismatch; }
  if seen.len!=0 { if id>=seen.len { return blot_error::Error.evidence_limit; } seen[id]=true; }
 }
 return blot_error::Error.none;
}
recursive fn walk(self_: View,id: Id,depth: i64,remaining: i64&,frames: ScopeFrame[:],scope_count: i64,region: bool,seen: bool[:],open: bool) -> Error {
 if depth>=128||remaining==0 { return blot_error::Error.evidence_limit; } remaining--; if id==0||id>=self_.nodes.len { return blot_error::Error.type_mismatch; }
 let n=node(self_,id); if region&&(n.tag!=Tag.bound||n.b!=2) { return blot_error::Error.type_mismatch; }
 if n.tag==Tag.bound {
  if n.c>=scope_count { if !open||n.a>=128||n.b>2||(region&&n.b!=2)||(!region&&n.b!=0) { return blot_error::Error.type_mismatch; } return blot_error::Error.none; }
  let owner=frames[scope_count-1-n.c].binders; if n.a>=owner.len { return blot_error::Error.type_mismatch; } let formal=node(self_,owner[n.a]);
  if formal.b!=n.b||(region&&n.b!=2)||(!region&&n.b!=0) { return blot_error::Error.type_mismatch; }
  if seen.len!=0 { if id>=seen.len { return blot_error::Error.evidence_limit; } seen[id]=true; } return blot_error::Error.none;
 }
 if n.tag==Tag.forall||n.tag==Tag.existential {
  if scope_count==frames.len||n.c>self_.extra.len||n.b>self_.extra.len-n.c { return blot_error::Error.type_mismatch; } let binders=children(self_,id);
  let err=binderList(self_,binders,seen,remaining); if err!=blot_error::Error.none { return err; }
  if n.tag==Tag.existential { for binder in binders { if node(self_,binder).b!=0 { return blot_error::Error.type_mismatch; } } }
  setScopeFrame(frames,scope_count,binders,quantifierGoals(self_,id)); let error=walk(self_,n.a,depth+1,remaining,frames,scope_count+1,false,seen,open); if error!=blot_error::Error.none { return error; }
  for goal in quantifierGoals(self_,id) { if remaining==0 { return blot_error::Error.evidence_limit; } remaining--; let endpoints: Id[4]=[goal.ty,goal.other,goal.result,goal.signature]; for endpoint in endpoints { if endpoint!=0 { let e=walk(self_,endpoint,depth+1,remaining,frames,scope_count+1,false,seen,open); if e!=blot_error::Error.none { return e; } } } } return blot_error::Error.none;
 }
 if n.tag==Tag.projection {
  if n.c>=self_.extra.len||self_.extra[n.c]>self_.extra.len-n.c-1 { return blot_error::Error.type_mismatch; } let count=self_.extra[n.c]; if self_.extra.len-n.c-1-count<3 { return blot_error::Error.type_mismatch; } let descriptor=projection(self_,id);
  if descriptor.member==0||descriptor.scope>=128||descriptor.goal>=4096 { return blot_error::Error.type_mismatch; }
  for arg in children(self_,id) { let err=walk(self_,arg,depth+1,remaining,frames,scope_count,false,seen,open); if err!=blot_error::Error.none { return err; } }
  if descriptor.scope>=scope_count { if !open { return blot_error::Error.type_mismatch; } return blot_error::Error.none; }
  let goals=frames[scope_count-1-descriptor.scope].goals; if descriptor.goal>=goals.len { return blot_error::Error.type_mismatch; }
  let err=blot_eval_evidence_projection::validate(self_,id,goals[descriptor.goal],remaining); if err!=blot_error::Error.none { return err; }
  if seen.len!=0 { if id>=seen.len { return blot_error::Error.evidence_limit; } seen[id]=true; } return blot_error::Error.none;
 }
 if n.tag==Tag.usage {
  if n.b>7 { return blot_error::Error.type_mismatch; } let loan=n.b==2||n.b==3; if loan!=(n.c!=0) { return blot_error::Error.type_mismatch; }
  let err=walk(self_,n.a,depth+1,remaining,frames,scope_count,false,seen,open); if err!=blot_error::Error.none { return err; } if loan { return walk(self_,n.c,depth+1,remaining,frames,scope_count,true,seen,open); } return blot_error::Error.none;
 }
 if n.tag==Tag.function||n.tag==Tag.state_provider {
  let a=walk(self_,n.a,depth+1,remaining,frames,scope_count,false,seen,open); if a!=blot_error::Error.none { return a; } let b=walk(self_,n.b,depth+1,remaining,frames,scope_count,false,seen,open); if b!=blot_error::Error.none { return b; }
  if n.tag==Tag.function { return walkRow(self_,n.c,depth+1,remaining,frames,scope_count,seen,open); } return walk(self_,n.c,depth+1,remaining,frames,scope_count,false,seen,open);
 }
 if n.tag==Tag.provider { let e=walk(self_,n.a,depth+1,remaining,frames,scope_count,false,seen,open); if e!=blot_error::Error.none { return e; } return walkRow(self_,n.c,depth+1,remaining,frames,scope_count,seen,open); }
 if n.tag==Tag.array||n.tag==Tag.list||n.tag==Tag.cursor||n.tag==Tag.resolver { return walk(self_,n.a,depth+1,remaining,frames,scope_count,false,seen,open); }
 if n.tag==Tag.product||n.tag==Tag.record||n.tag==Tag.nominal {
  var start=n.a as i64; var count=n.b as i64;
  if n.tag==Tag.record { if count>0x7fffffff { return blot_error::Error.evidence_limit; } count*=2; }
  if n.tag==Tag.nominal { if n.c>=self_.extra.len { return blot_error::Error.type_mismatch; } start=n.c+1; count=self_.extra[n.c]; }
  if start>self_.extra.len||count>self_.extra.len-start { return blot_error::Error.type_mismatch; }
  for child,index in self_.extra[start..start+count] { if n.tag==Tag.record&&index%2==0 { continue; } let err=walk(self_,child,depth+1,remaining,frames,scope_count,false,seen,open); if err!=blot_error::Error.none { return err; } } return blot_error::Error.none;
 }
 if n.tag==Tag.scoped||n.tag==Tag.absent||n.tag==Tag.erased_proof { return blot_error::Error.unresolved_type; } return blot_error::Error.none;
}
recursive fn walkRow(self_: View,row: u32,depth: i64,remaining: i64&,frames: ScopeFrame[:],scope_count: i64,seen: bool[:],open: bool) -> Error {
 if row==0 { return blot_error::Error.none; } if depth>=128||remaining==0||row>=self_.effects.rows.len { return blot_error::Error.evidence_limit; } remaining--;
 let formal=self_.effects.rows[row].formal;
 if formal!=0 {
  if formal>=self_.nodes.len||remaining==0 { return blot_error::Error.type_mismatch; } remaining--; let leaf=node(self_,formal);
  if leaf.tag!=Tag.bound||leaf.b!=1||leaf.a>=128||leaf.c>=128 { return blot_error::Error.type_mismatch; }
  if leaf.c>=scope_count { if !open { return blot_error::Error.type_mismatch; } }
  else { let owner=frames[scope_count-1-leaf.c].binders; if leaf.a>=owner.len||node(self_,owner[leaf.a]).b!=1 { return blot_error::Error.type_mismatch; } }
  if seen.len!=0 { if formal>=seen.len { return blot_error::Error.evidence_limit; } seen[formal]=true; }
 }
 for label in self_.effects.rowLabels(row) { if label==0||label>=self_.effects.operations.len||remaining==0 { return blot_error::Error.type_mismatch; } remaining--; for arg in self_.effects.operationArguments(label) { let err=walk(self_,arg,depth+1,remaining,frames,scope_count,false,seen,open); if err!=blot_error::Error.none { return err; } } } return blot_error::Error.none;
}
fn openQuantifier(self_: View,id: Id,remaining: i64&,seen: bool[:]) -> Error { let e=validateGoalTablesWithBudget(self_,remaining); if e!=blot_error::Error.none { return e; } return openQuantifierValidated(self_,id,remaining,seen); }
fn openQuantifierValidated(self_: View,id: Id,remaining: i64&,seen: bool[:]) -> Error { var frames: ScopeFrame[128]=[ScopeFrame {..};128]; return walk(self_,id,0,remaining,frames,0,false,seen,true); }
fn body(self_: View,id: Id,binders: const Id[:],depth: i64,remaining: i64&,seen: bool[:]) -> Error { let e=validateGoalTablesWithBudget(self_,remaining); if e!=blot_error::Error.none { return e; } var frames: ScopeFrame[128]=[ScopeFrame {..};128]; let error=binderList(self_,binders,seen,remaining); if error!=blot_error::Error.none { return error; } frames[0]=ScopeFrame {binders,default<const Goal[:]>()}; return walk(self_,id,depth,remaining,frames,1,false,seen,false); }
fn bodyWithGoalsValidated(self_: View,id: Id,binders: const Id[:],goals: const Goal[:],remaining: i64&,seen: bool[:]) -> Error { var frames: ScopeFrame[128]=[ScopeFrame {..};128]; let err=binderList(self_,binders,seen,remaining); if err!=blot_error::Error.none { return err; } frames[0]=ScopeFrame {binders,goals}; return walk(self_,id,0,remaining,frames,1,false,seen,true); }
fn openBodyWithGoals(self_: View,id: Id,binders: const Id[:],goals: const Goal[:],remaining: i64&,seen: bool[:]) -> Error { let err=validateGoalTablesWithBudget(self_,remaining); if err!=blot_error::Error.none { return err; } return bodyWithGoalsValidated(self_,id,binders,goals,remaining,seen); }
fn openBody(self_: View,id: Id,binders: const Id[:],remaining: i64&,seen: bool[:]) -> Error { return openBodyWithGoals(self_,id,binders,[],remaining,seen); }
fn closed(self_: View,id: Id,depth: i64,remaining: i64&) -> Error { let err=validateGoalTablesWithBudget(self_,remaining); if err!=blot_error::Error.none { return err; } var frames: ScopeFrame[128]=[ScopeFrame {..};128]; return walk(self_,id,depth,remaining,frames,0,false,default<bool[:]>(),false); }
struct Snapshot { owner_id: u64=blot_native::fresh_owner_id(),nodes: const Node[:],extra: const Id[:],effects: blot_check_effect_evidence::Snapshot,quantifier_goals: const QuantifierGoals[:]=default<const QuantifierGoals[:]>(),quantifier_obligations: const Goal[:]=default<const Goal[:]>() }
fn view(self_: const Snapshot&) -> View { return View {self_.owner_id,self_.nodes,self_.extra,self_.effects.view(),self_.quantifier_goals,self_.quantifier_obligations}; }
struct NodeBuffer { storage: Node[:]=default<Node[:]>(),items: Node[:]=default<Node[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_NodeBuffer: Node[>..]=[];
fn ensure(self_: NodeBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_NodeBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: NodeBuffer&,value: Node) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_NodeBuffer); self_.len=self_.items.len; }
fn append(self_: NodeBuffer&,values: const Node[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_NodeBuffer); self_.len=self_.items.len; }
fn resize(self_: NodeBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: NodeBuffer&,length: i64,value: Node) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: NodeBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: NodeBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_NodeBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct WordBuffer { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_WordBuffer: u32[>..]=[];
fn ensure(self_: WordBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_WordBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: WordBuffer&,value: u32) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_WordBuffer); self_.len=self_.items.len; }
fn append(self_: WordBuffer&,values: const u32[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_WordBuffer); self_.len=self_.items.len; }
fn resize(self_: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: WordBuffer&,length: i64,value: u32) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: WordBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: WordBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_WordBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
// Resolver callbacks may reenter with another source graph. Each active frame
// retains its own binder IDs; scalar ranges address these owned snapshots.
struct ProjectionOwner { start: i64=0,len: i64=0 }
struct OwnersBuffer { storage: ProjectionOwner[:]=default<ProjectionOwner[:]>(),items: ProjectionOwner[:]=default<ProjectionOwner[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_OwnersBuffer: ProjectionOwner[>..]=[];
reusable[] var projection_owner_binders: u32[>..]=[];
fn ownerBinders(frame: ProjectionOwner) -> const u32[:] { return projection_owner_binders[frame.start..frame.start+frame.len]; }
fn push(self_: OwnersBuffer&,values: const u32[:]) {
 if self_.failure!=blot_error::Error.none { return; }
 let length=self_.items.len;
 self_.failure=blot_support_pooled_buffer::ensure(self_,length+1,pool_OwnersBuffer);
 if self_.failure!=blot_error::Error.none { return; }
 let owned=projection_owner_binders.alloc_slice(values.len);
 for value,index in values { owned[index]=value; }
 var start: i64=0; if owned.len!=0 { start=projection_owner_binders.index_of(owned[0]); }
 self_.storage[length]=ProjectionOwner {start,owned.len}; self_.items=self_.storage[..length+1]; self_.len=self_.items.len;
}
fn resize(self_: OwnersBuffer&,length: i64) {
 assert(length>=0&&length<=self_.len);
 for frame in self_.items[length..] { if frame.len!=0 { projection_owner_binders.free_slice(projection_owner_binders[frame.start..frame.start+frame.len]); } }
 blot_support_pooled_buffer::resize(self_,length); self_.len=length;
}
fn clear(self_: OwnersBuffer&) { resize(self_,0); self_.failure=blot_error::Error.none; }
fn deinit(self_: OwnersBuffer&) { clear(self_); blot_support_pooled_buffer::deinit(self_,pool_OwnersBuffer); }
struct QuantifierBuffer { storage: QuantifierGoals[:]=default<QuantifierGoals[:]>(),items: QuantifierGoals[:]=default<QuantifierGoals[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_QuantifierBuffer: QuantifierGoals[>..]=[];
fn ensure(self_: QuantifierBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_QuantifierBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: QuantifierBuffer&,value: QuantifierGoals) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_QuantifierBuffer); self_.len=self_.items.len; }
fn append(self_: QuantifierBuffer&,values: const QuantifierGoals[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_QuantifierBuffer); self_.len=self_.items.len; }
fn resize(self_: QuantifierBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: QuantifierBuffer&,length: i64,value: QuantifierGoals) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: QuantifierBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: QuantifierBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_QuantifierBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct GoalBuffer { storage: Goal[:]=default<Goal[:]>(),items: Goal[:]=default<Goal[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_GoalBuffer: Goal[>..]=[];
fn ensure(self_: GoalBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_GoalBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: GoalBuffer&,value: Goal) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_GoalBuffer); self_.len=self_.items.len; }
fn append(self_: GoalBuffer&,values: const Goal[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_GoalBuffer); self_.len=self_.items.len; }
fn resize(self_: GoalBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: GoalBuffer&,length: i64,value: Goal) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: GoalBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: GoalBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_GoalBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct Buckets { count: i64=0,slots: dictionary_slot<u64,u32>[:]=default<dictionary_slot<u64,u32>[:]>() }
reusable[] var bucket_slots: dictionary_slot<u64,u32>[>..]=[];
fn get(self_: const Buckets&,key: u64) -> u32? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn insert(self_: Buckets&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,bucket_slots); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: Buckets&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn deinit(self_: Buckets&) { if self_.slots.len!=0 { bucket_slots.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,u32>[:]>(); self_.count=0; }
fn reserve(self_: Buckets&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return blot_error::Error.out_of_memory; } var capacity=max(8,self_.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self_.slots.len { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::grow(view,capacity,bucket_slots); self_.count=view.count; self_.slots=view.slots; } return blot_error::Error.none; }
fn copyBuckets(destination: Buckets&,source: const Buckets&) { if destination.slots.len!=0 { bucket_slots.free_slice(destination.slots); } destination.slots=default<dictionary_slot<u64,u32>[:]>(); destination.count=source.count; if source.slots.len!=0 { destination.slots=bucket_slots.alloc_slice(source.slots.len); for slot,index in source.slots { destination.slots[index]=slot; } } }
struct State { owner_id: u64=0,generation: u64=0,effects: blot_check_effect_evidence::Store=blot_check_effect_evidence::Store {},nodes: NodeBuffer=NodeBuffer {},extra: WordBuffer=WordBuffer {},next: WordBuffer=WordBuffer {},buckets: Buckets=Buckets {},projection_owners: OwnersBuffer=OwnersBuffer {},projection_quantifiers: WordBuffer=WordBuffer {},quantifier_goals: QuantifierBuffer=QuantifierBuffer {},quantifier_obligations: GoalBuffer=GoalBuffer {} }
reusable var states: State[>..]=[];
var next_generation: u64=1;
var inactive_NodeBuffer: NodeBuffer=NodeBuffer {};
var inactive_WordBuffer: WordBuffer=WordBuffer {};
var inactive_Buckets: Buckets=Buckets {};
var inactive_OwnersBuffer: OwnersBuffer=OwnersBuffer {};
var inactive_QuantifierBuffer: QuantifierBuffer=QuantifierBuffer {};
var inactive_GoalBuffer: GoalBuffer=GoalBuffer {};
var inactive_effects: blot_check_effect_evidence::Store=blot_check_effect_evidence::Store {};
struct Store { owner_id: u64=0,lease: u32=0,generation: u64=0,effects: blot_check_effect_evidence::Store& =inactive_effects,nodes: NodeBuffer& =inactive_NodeBuffer,extra: WordBuffer& =inactive_WordBuffer,next: WordBuffer& =inactive_WordBuffer,buckets: Buckets& =inactive_Buckets,projection_owners: OwnersBuffer& =inactive_OwnersBuffer,projection_quantifiers: WordBuffer& =inactive_WordBuffer,quantifier_goals: QuantifierBuffer& =inactive_QuantifierBuffer,quantifier_obligations: GoalBuffer& =inactive_GoalBuffer }
fn valid(self_: const Store&) -> bool { return self_.lease!=0&&self_.lease-1<states.len&&states[self_.lease-1].owner_id==self_.owner_id&&states[self_.lease-1].generation==self_.generation&&self_.owner_id!=0; }
fn init() -> Store,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Store {},blot_error::Error.out_of_memory; } let effects,error=blot_check_effect_evidence::init(); if error!=blot_error::Error.none { return Store {},error; } let generation=next_generation; next_generation++; let owner=blot_native::fresh_owner_id(); let index=states.alloc_index(State {owner_id:owner,generation:generation,effects:effects}); let state: State& =states[index]; var self_=Store {owner_id:owner,lease:(index+1) as u32,generation:generation,effects:state.effects,nodes:state.nodes,extra:state.extra,next:state.next,buckets:state.buckets,projection_owners:state.projection_owners,projection_quantifiers:state.projection_quantifiers,quantifier_goals:state.quantifier_goals,quantifier_obligations:state.quantifier_obligations}; for tag in [Tag.absent,Tag.unit,Tag.boolean,Tag.unsigned32,Tag.floating32,Tag.never] { self_.nodes.push(Node {tag}); self_.next.push(0); } return self_,blot_error::Error.none; }
fn view(self_: const Store&) -> View { assert(valid(self_)); return View {self_.owner_id,self_.nodes.items,self_.extra.items,self_.effects.view(),self_.quantifier_goals.items,self_.quantifier_obligations.items}; }
fn node(self_: const Store&,id: Id) -> Node { return view(self_).node(id); }
fn children(self_: const Store&,id: Id) -> const Id[:] { return view(self_).children(id); }
fn goalEqual(left: const Goal[:],right: const Goal[:]) -> bool { if left.len!=right.len { return false; } for a,index in left { if a!=right[index] { return false; } } return true; }
fn put32<B>(bytes: B&,value: u32) { for shift in 0..4 { bytes.push((value>>((shift*8) as u32)) as u8); } }
fn fingerprint(tag: Tag,a: u32,b: u32,row: u32,values: const Id[:],goals: const Goal[:]) -> u64 {
 var bytes=ByteBuffer {};  bytes.push(tagCode(tag)); put32(bytes,a); put32(bytes,b);
 if goals.len==0 { put32(bytes,row); }
 for word in values { put32(bytes,word); }
 for goal in goals {
  put32(bytes,goal.ty); bytes.push(blot_check_types::obligationKindCode(goal.kind) as u8); put32(bytes,goal.name); put32(bytes,goal.result); put32(bytes,goal.other); put32(bytes,goal.signature); bytes.push(blot_check_types::operatorCode(goal.operator) as u8); put32(bytes,goal.identity.unit); put32(bytes,goal.identity.decl); var explicit: u8=0; if goal.explicit { explicit=1; } bytes.push(explicit);
 }
 let __cleanup_result_1_0: u64 = blot_parse_symbols::wyhash(bytes.items); bytes.deinit(); return __cleanup_result_1_0;
 bytes.deinit(); }
fn intern(self_: Store,tag: Tag,a: u32,b: u32,values: const Id[:]) -> Id,Error { return internWithEffects(self_,tag,a,b,0,values); }
fn internWithEffects(self_: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:]) -> Id,Error { return internFields(self_,tag,a,b,row,values); }
fn internStateProvider(self_: Store,read: Id,write: Id,state: Id) -> Id,Error { return internFields(self_,Tag.state_provider,read,write,state,[]); }
fn internFields(self_: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:]) -> Id,Error {
 if (tag==Tag.forall||tag==Tag.existential)&&values.len==0 {
  if b==0||b>128 { return 0,blot_error::Error.type_mismatch; } var binders: Id[128];
  for ordinal in 0..b { let binder,err=internNormalizedFields(self_,Tag.bound,ordinal as u32,0,0,[]); if err!=blot_error::Error.none { return 0,err; } binders[ordinal]=binder; } return internNormalizedFields(self_,tag,a,b,row,binders[..b]);
 }
 return internNormalizedFields(self_,tag,a,b,row,values);
}
fn internNormalizedFields(self_: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:]) -> Id,Error {
 var owned=WordBuffer {};  for value in values { owned.push(value); }
 if tag==Tag.record {
  if owned.len%2!=0 { let __cleanup_result_2_0: Id = 0; let __cleanup_result_2_1: Error = blot_error::Error.type_mismatch; owned.deinit(); return __cleanup_result_2_0, __cleanup_result_2_1; }
  // Pair insertion sort keeps field identities adjacent to their evidence.
  var i=2; while i<owned.len { let name=owned.items[i]; let evidence=owned.items[i+1]; var j=i; while j>=2&&owned.items[j-2]>name { owned.items[j]=owned.items[j-2]; owned.items[j+1]=owned.items[j-1]; j-=2; } owned.items[j]=name; owned.items[j+1]=evidence; i+=2; }
  i=2; while i<owned.len { if owned.items[i]==owned.items[i-2] { let __cleanup_result_3_0: Id = 0; let __cleanup_result_3_1: Error = blot_error::Error.type_mismatch; owned.deinit(); return __cleanup_result_3_0, __cleanup_result_3_1; } i+=2; }
 }
 let __cleanup_result_4_0, __cleanup_result_4_1 = internWithEffectsHashed(self_,tag,a,b,row,owned.items,fingerprint(tag,a,b,row,owned.items,[])); owned.deinit(); return __cleanup_result_4_0, __cleanup_result_4_1;
 owned.deinit(); }
fn internHashed(self_: Store,tag: Tag,a: u32,b: u32,values: const Id[:],hash: u64) -> Id,Error { return internWithEffectsHashed(self_,tag,a,b,0,values,hash); }
fn internWithEffectsHashed(self_: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:],hash: u64) -> Id,Error { return internGoalFields(self_,tag,a,b,row,values,[],hash); }
fn internProjection(self_: Store,identity: Identity,member: u32,arguments: const Id[:],scope: u32,goal: u32) -> Id,Error { var words=WordBuffer {};  words.append(arguments); words.push(member); words.push(scope); words.push(goal); let __cleanup_result_5_0, __cleanup_result_5_1 = intern(self_,Tag.projection,identity.unit,identity.decl,words.items); words.deinit(); return __cleanup_result_5_0, __cleanup_result_5_1;  words.deinit(); }
fn internQuantifiedWithGoals(self_: Store,tag: Tag,body: Id,binders: const Id[:],goals: const Goal[:]) -> Id,Error {
 if tag!=Tag.forall&&tag!=Tag.existential { return 0,blot_error::Error.type_mismatch; }
 if goals.len==0 { return intern(self_,tag,body,binders.len as u32,binders); }
 return internGoalFields(self_,tag,body,binders.len as u32,0,binders,goals,fingerprint(tag,body,binders.len as u32,0,binders,goals));
}
fn internGoalFields(self_: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:],goals: const Goal[:],hash: u64) -> Id,Error {
 if tag!=Tag.state_provider&&tag!=Tag.scoped&&tag!=Tag.usage&&tag!=Tag.bound&&(row>=self_.effects.rows.len||(row!=0&&tag!=Tag.function&&tag!=Tag.provider)) { return 0,blot_error::Error.type_mismatch; }
 if tag==Tag.absent { return 0,blot_error::Error.unresolved_type; }
 if tag==Tag.usage {
  if a==0||a>=self_.nodes.len||b>7||values.len!=0 { return 0,blot_error::Error.type_mismatch; } let loan=b==2||b==3; if loan!=(row!=0) { return 0,blot_error::Error.type_mismatch; }
  if loan&&(row>=self_.nodes.len||node(self_,row).tag!=Tag.bound||node(self_,row).b!=2) { return 0,blot_error::Error.type_mismatch; }
 } else if tag==Tag.erased_proof { if a!=0||b!=0||values.len!=0 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.unit||tag==Tag.boolean||tag==Tag.unsigned32||tag==Tag.floating32||tag==Tag.never { if a!=0||b!=0||values.len!=0 { return 0,blot_error::Error.type_mismatch; } return tagCode(tag) as u32,blot_error::Error.none; }
 else if tag==Tag.forall||tag==Tag.existential {
  if a==0||a>=self_.nodes.len||b==0||b>128||row!=0||values.len!=b { return 0,blot_error::Error.type_mismatch; }
  var remaining: i64=4096; let e=bodyWithGoalsValidated(view(self_),a,values,goals,remaining,default<bool[:]>()); if e!=blot_error::Error.none { return 0,e; }
  if tag==Tag.existential { for binder in values { if node(self_,binder).b!=0 { return 0,blot_error::Error.type_mismatch; } } }
  for goal in goals {
   if goal.ty==0||blot_check_types::obligationKindCode(goal.kind)>blot_check_types::obligationKindCode(blot_check_types::ObligationKind.task_receive)||blot_check_types::operatorCode(goal.operator)>blot_check_types::operatorCode(blot_check_types::Operator.shift_right) { return 0,blot_error::Error.type_mismatch; }
   let endpoints: Id[4]=[goal.ty,goal.other,goal.result,goal.signature]; for endpoint in endpoints { if endpoint!=0 { let error=bodyWithGoalsValidated(view(self_),endpoint,values,goals,remaining,default<bool[:]>()); if error!=blot_error::Error.none { return 0,error; } } }
  }
 } else if tag==Tag.scoped { if a==0||a>=self_.nodes.len||node(self_,a).tag!=Tag.nominal||b==0||row==0||values.len!=0 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.bound { if a>=128||b>2||row>=128||values.len!=0 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.function { if values.len!=0||a==0||b==0||a>=self_.nodes.len||b>=self_.nodes.len { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider { if values.len!=0||a==0||a>=self_.nodes.len||b!=0 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.state_provider { if values.len!=0||a==0||b==0||row==0||a>=self_.nodes.len||b>=self_.nodes.len||row>=self_.nodes.len { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.product||tag==Tag.record { if a!=0||b!=0 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.projection { if a==0||b==0||values.len<3||values[values.len-3]==0||values[values.len-2]>=128||values[values.len-1]>=4096 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.nominal { if a==0 { return 0,blot_error::Error.type_mismatch; } }
 else if tag==Tag.type_constructor { if a==0||b==0||values.len!=0 { return 0,blot_error::Error.type_mismatch; } }
 if tag==Tag.provider&&node(self_,a).tag!=Tag.nominal&&node(self_,a).tag!=Tag.scoped { return 0,blot_error::Error.type_mismatch; }
 if (tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider)&&node(self_,a).tag==Tag.erased_proof { return 0,blot_error::Error.type_mismatch; }
 if tag==Tag.state_provider&&((node(self_,a).tag!=Tag.nominal&&node(self_,a).tag!=Tag.scoped)||(node(self_,b).tag!=Tag.nominal&&node(self_,b).tag!=Tag.scoped)) { return 0,blot_error::Error.type_mismatch; }
 for value,index in values {
  if tag==Tag.projection&&index>=values.len-3 { continue; }
  if tag==Tag.record&&index%2==0 { if value==0 { return 0,blot_error::Error.type_mismatch; } }
  else if value==0||value>=self_.nodes.len||node(self_,value).tag==Tag.erased_proof { return 0,blot_error::Error.type_mismatch; }
 }
 var candidate: Id=0; let bucket=self_.buckets.get(hash); if bucket!=null { candidate=bucket; }
 while candidate!=0 {
  let n=node(self_,candidate); var same=n.tag==tag;
  if same {
   if tag==Tag.product||tag==Tag.record { same=children(self_,candidate)==values; }
   else if tag==Tag.nominal||tag==Tag.forall||tag==Tag.existential { same=n.a==a&&n.b==b&&children(self_,candidate)==values; }
   else if tag==Tag.projection { same=n.a==a&&n.b==b&&self_.extra.items[n.c+1..n.c+1+self_.extra.items[n.c]+3]==values; }
   else { same=n.a==a&&n.b==b&&n.c==row; }
  }
  if same&&goalEqual(view(self_).quantifierGoals(candidate),goals) { return candidate,blot_error::Error.none; } candidate=self_.next.items[candidate];
 }
 if self_.nodes.len>=0xffffffff||values.len>=0xffffffff||self_.extra.len>0xffffffff-values.len-1 { return 0,blot_error::Error.evidence_limit; }
 if goals.len>0xffffffff-self_.quantifier_obligations.len { return 0,blot_error::Error.evidence_limit; }
 var n=Node {tag,a,b,row};
 if tag==Tag.product||tag==Tag.record { n.a=self_.extra.len as u32; n.b=values.len as u32; if tag==Tag.record { n.b/=2; } self_.extra.append(values); }
 else if tag==Tag.forall||tag==Tag.existential { n.c=self_.extra.len as u32; self_.extra.append(values); }
 else if tag==Tag.nominal||tag==Tag.projection { n.c=self_.extra.len as u32; var count=values.len; if tag==Tag.projection { count-=3; } self_.extra.push(count as u32); self_.extra.append(values); }
 let id=self_.nodes.len as Id;
 if goals.len!=0 { self_.quantifier_goals.push(QuantifierGoals {id,blot_check_types::List {self_.quantifier_obligations.len as u32,goals.len as u32}}); self_.quantifier_obligations.append(goals); }
 var prior: Id=0; let previous=self_.buckets.get(hash); if previous!=null { prior=previous; } self_.nodes.push(n); self_.next.push(prior); self_.buckets.insert(hash,id); return id,blot_error::Error.none;
}
fn containsAbstract(self_: const Store&,id: Id) -> bool,Error { var remaining: i64=4096; return abstractDepth(self_,id,0,remaining); }
recursive fn abstractDepth(self_: const Store&,id: Id,depth: i64,remaining: i64&) -> bool,Error {
 if depth>=128||remaining==0 { return false,blot_error::Error.evidence_limit; } remaining--; let n=node(self_,id);
 if n.tag==Tag.bound||n.tag==Tag.projection { return true,blot_error::Error.none; } if n.tag==Tag.forall||n.tag==Tag.existential { return false,blot_error::Error.none; }
 if n.tag==Tag.function||n.tag==Tag.state_provider {
  let a,e=abstractDepth(self_,n.a,depth+1,remaining); if e!=blot_error::Error.none||a { return a,e; } let b,error=abstractDepth(self_,n.b,depth+1,remaining); if error!=blot_error::Error.none||b { return b,error; }
  if n.tag==Tag.state_provider { return abstractDepth(self_,n.c,depth+1,remaining); }
 } else if n.tag==Tag.scoped||n.tag==Tag.usage||n.tag==Tag.array||n.tag==Tag.list||n.tag==Tag.cursor||n.tag==Tag.resolver||n.tag==Tag.provider { return abstractDepth(self_,n.a,depth+1,remaining); }
 else if n.tag==Tag.product||n.tag==Tag.record||n.tag==Tag.nominal { for child,index in children(self_,id) { if n.tag==Tag.record&&index%2==0 { continue; } let found,err=abstractDepth(self_,child,depth+1,remaining); if err!=blot_error::Error.none||found { return found,err; } } }
 return false,blot_error::Error.none;
}
struct ProjectionWork<S,R> { destination: Store,source: S,mappings: const Mapping[:],rows: const RowMapping[:],resolver: ProjectionResolver<R>,failure: Error=blot_error::Error.none }
fn accept<S,R>(work: ProjectionWork<S,R>&,id: Id,error: Error) -> Id { if work.failure==blot_error::Error.none { work.failure=error; } return id; }
fn reject<S,R>(work: ProjectionWork<S,R>&,error: Error) -> Id { if work.failure==blot_error::Error.none { work.failure=error; } return 0; }
recursive fn projectDepth<S,R>(work: ProjectionWork<S,R>&,ty: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,parent_height: u16?) -> Id {
 if work.failure!=blot_error::Error.none { return 0; } if depth>=1024||budget==0 { return reject(work,blot_error::Error.evidence_limit); }
 if work.resolver.enabled {
  if depth>=256||work.resolver.remaining==0 { return reject(work,blot_error::Error.evidence_limit); } work.resolver.remaining--;
  if ty>5&&memo!=null { let answer=blot_reuse_projection_cache::get(memo.answers,ty); if answer!=null { let a=answer; if depth+a.height>256 { return reject(work,blot_error::Error.evidence_limit); } budget--; if parent_height!=null&&parent_height<a.height+1 { parent_height = a.height+1; } return a.value; } }
 }
 if retained&&ty>5&&memo!=null {
  let answer=blot_reuse_projection_cache::get(memo.answers,ty); if answer!=null { let a=answer; if depth+a.height>1024||budget<a.visits { return reject(work,blot_error::Error.evidence_limit); } budget-=a.visits; if parent_height!=null&&parent_height<a.height+1 { parent_height = a.height+1; } return a.value; }
 }
 let before=budget; budget--; var height: u16=1; let result=projectNodeDepth(work,ty,depth,budget,retained,memo,height); if work.failure!=blot_error::Error.none { return 0; }
 if retained||memo!=null {
  if parent_height!=null&&parent_height<height+1 { parent_height = height+1; }
  if ty>5&&memo!=null { var visits: u32=1; if retained { visits=(before-budget) as u32; } blot_reuse_projection_cache::insert(memo.answers,ty,blot_reuse_projection_cache::Answer {result,visits,height}); }
 }
 return result;
}
recursive fn projectRowDepth<S,R>(work: ProjectionWork<S,R>&,row: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,parent_height: u16?) -> u32 {
 if work.failure!=blot_error::Error.none { return 0; } if depth>=1024||budget==0 { return reject(work,blot_error::Error.evidence_limit); } budget--;
 if work.resolver.enabled { if depth>=256||work.resolver.remaining==0 { return reject(work,blot_error::Error.evidence_limit); } work.resolver.remaining--; }
 var height: u16=1; let result=projectRowBody(work,row,depth,budget,retained,memo,height);
 if memo!=null&&parent_height!=null&&parent_height<height+1 { parent_height = height+1; } return result;
}
recursive fn projectNodeDepth<S,R>(work: ProjectionWork<S,R>&,ty: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,height: u16&) -> Id {
 if work.failure!=blot_error::Error.none { return 0; } let self_=work.destination; let source=work.source;
 for mapping in mappingItems(work.mappings) { if mapping.variable==ty {
  if mapping.evidence==0||mapping.evidence>=self_.nodes.len { return reject(work,blot_error::Error.type_mismatch); } let leaf=node(self_,mapping.evidence);
  if leaf.tag==Tag.erased_proof&&source.node(ty).tag!=blot_check_types::Tag.erased_proof { return reject(work,blot_error::Error.type_mismatch); }
  if leaf.tag==Tag.bound {
   var scope=self_.projection_owners.len;
   while scope!=0 { scope--; for binder in ownerBinders(self_.projection_owners.items[scope]) { if binder==ty { let levels=self_.projection_owners.len-1-scope; if levels>=128||leaf.c>127-levels { return reject(work,blot_error::Error.evidence_limit); } let id,err=internWithEffects(self_,Tag.bound,leaf.a,leaf.b,leaf.c+levels as u32,[]); return accept(work,id,err); } } }
  }
  return mapping.evidence;
 } }
 let n=source.node(ty); let tag=n.tag;
 if tag==blot_check_types::Tag.usage {
  var region: Id=0; if n.c!=0 { region=projectDepth(work,n.c,depth+1,budget,retained,memo,height); }
  let base=projectDepth(work,n.a,depth+1,budget,retained,memo,height); if work.failure!=blot_error::Error.none { return 0; } let id,err=internWithEffects(self_,Tag.usage,base,n.b,region,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.forall||tag==blot_check_types::Tag.existential {
  let source_binders=source.list(blot_check_types::List {n.b,n.c});
  if tag==blot_check_types::Tag.forall { var complete=true; for binder in source_binders { var found=false; for mapping in mappingItems(work.mappings) { if mapping.variable==binder { found=true; break; } } complete=complete&&found; } if complete&&source.quantifierGoals(ty).len==0 { return projectDepth(work,n.a,depth+1,budget,retained,memo,height); } }
  if depth>=128||n.c==0||n.c>128 { return reject(work,blot_error::Error.evidence_limit); }
  var owned=MappingBuffer {};
  for binder,ordinal in source_binders { let leaf=source.node(binder); if leaf.tag!=blot_check_types::Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { let __cleanup_result_6_0: Id = reject(work,blot_error::Error.unresolved_type); owned.deinit(); return __cleanup_result_6_0; } let id,error=intern(self_,Tag.bound,ordinal as u32,leaf.b,[]); if error!=blot_error::Error.none { let __cleanup_result_7_0: Id = reject(work,error); owned.deinit(); return __cleanup_result_7_0; } owned.push(Mapping {binder,id}); }
  owned.append(work.mappings); self_.projection_owners.push(source_binders); self_.projection_quantifiers.push(ty);
  let saved_mappings=work.mappings; work.mappings=owned.items; var body_budget=budget; if body_budget>4096 { body_budget=4096; } let available=body_budget;

  let body=projectDepth(work,n.a,depth+1,body_budget,false,null,height); var result_tag=Tag.existential; if tag==blot_check_types::Tag.forall { result_tag=Tag.forall; }
  var binders: Id[128]; for mapping,index in owned.items[..n.c] { binders[index]=mapping.evidence; } var goals=GoalBuffer {};
  for goal in source.quantifierGoals(ty) {
   if body_budget==0 { let __cleanup_result_87_0: Id = reject(work,blot_error::Error.evidence_limit); { work.mappings=saved_mappings; self_.projection_owners.resize(self_.projection_owners.len-1); self_.projection_quantifiers.resize(self_.projection_quantifiers.len-1); budget-=available-body_budget; } let __cleanup_result_8_0: Id = __cleanup_result_87_0; goals.deinit(); owned.deinit(); return __cleanup_result_8_0; } body_budget--; var value=Goal {ty:0,kind:goal.kind,name:goal.name,operator:goal.operator,identity:goal.identity,explicit:goal.explicit};
   if goal.ty!=0 { value.ty=projectDepth(work,goal.ty,depth+1,body_budget,false,null,height); } if goal.other!=0 { value.other=projectDepth(work,goal.other,depth+1,body_budget,false,null,height); } if goal.result!=0 { value.result=projectDepth(work,goal.result,depth+1,body_budget,false,null,height); } if goal.signature!=0 { value.signature=projectDepth(work,goal.signature,depth+1,body_budget,false,null,height); } goals.push(value);
  }
  if work.failure!=blot_error::Error.none { let __cleanup_result_88_0: Id = 0; { work.mappings=saved_mappings; self_.projection_owners.resize(self_.projection_owners.len-1); self_.projection_quantifiers.resize(self_.projection_quantifiers.len-1); budget-=available-body_budget; } let __cleanup_result_9_0: Id = __cleanup_result_88_0; goals.deinit(); owned.deinit(); return __cleanup_result_9_0; } let id,err=internQuantifiedWithGoals(self_,result_tag,body,binders[..n.c],goals.items); let __cleanup_result_89_0: Id = accept(work,id,err); { work.mappings=saved_mappings; self_.projection_owners.resize(self_.projection_owners.len-1); self_.projection_quantifiers.resize(self_.projection_quantifiers.len-1); budget-=available-body_budget; } let __cleanup_result_10_0: Id = __cleanup_result_89_0; goals.deinit(); owned.deinit(); return __cleanup_result_10_0;
  { work.mappings=saved_mappings; self_.projection_owners.resize(self_.projection_owners.len-1); self_.projection_quantifiers.resize(self_.projection_quantifiers.len-1); budget-=available-body_budget; }  goals.deinit(); owned.deinit(); }
 if tag==blot_check_types::Tag.scoped {
  let descriptor=projectDepth(work,n.a,depth+1,budget,retained,memo,height); var instance=blot_check_types::selectionAtom(source,Identity {n.b,n.c});
  if instance.unit==0 { let owner_id=projectDepth(work,n.c,depth+1,budget,retained,memo,height); if work.failure!=blot_error::Error.none { return 0; } let owner=node(self_,owner_id); if owner.tag!=Tag.scoped { return reject(work,blot_error::Error.unresolved_type); } instance=Identity {owner.b,owner.c}; }
  if instance.unit==0||instance.decl==0 { return reject(work,blot_error::Error.unresolved_type); } let id,err=internWithEffects(self_,Tag.scoped,descriptor,instance.unit,instance.decl,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.instance_version||tag==blot_check_types::Tag.bound||tag==blot_check_types::Tag.rigid||tag==blot_check_types::Tag.instance_selection||tag==blot_check_types::Tag.variable||tag==blot_check_types::Tag.absent { return reject(work,blot_error::Error.unresolved_type); }
 if tag==blot_check_types::Tag.erased_proof { let id,err=intern(self_,Tag.erased_proof,0,0,[]); return accept(work,id,err); }
 if tag==blot_check_types::Tag.unit { return 1; } if tag==blot_check_types::Tag.boolean { return 2; } if tag==blot_check_types::Tag.unsigned32 { return 3; } if tag==blot_check_types::Tag.floating32 { return 4; } if tag==blot_check_types::Tag.never { return 5; }
 if tag==blot_check_types::Tag.projection {
  let input=source.nominalArguments(n); var arguments=WordBuffer {};  for root in input { arguments.push(projectDepth(work,root,depth+1,budget,retained,memo,height)); }
  var owner_index=self_.projection_quantifiers.len;
  while owner_index!=0 {
   owner_index--; let owner=self_.projection_quantifiers.items[owner_index];
   for goal,ordinal in source.quantifierGoals(owner) {
    if budget==0 { let __cleanup_result_11_0: Id = reject(work,blot_error::Error.evidence_limit); arguments.deinit(); return __cleanup_result_11_0; } budget--;
    if goal.kind!=blot_check_types::ObligationKind.contract||goal.identity.unit!=n.a||goal.identity.decl!=n.b { continue; } let tuple=source.node(goal.ty); if tuple.tag!=blot_check_types::Tag.product||tuple.b!=input.len { continue; }
    var matches=true; for expected,index in source.list(blot_check_types::List {tuple.a,tuple.b}) { let projected=projectDepth(work,expected,depth+1,budget,retained,memo,height); if projected!=arguments.items[index] { matches=false; } }
    if matches&&work.failure==blot_error::Error.none { let id,err=internProjection(self_,Identity {n.a,n.b},source.projectionMember(n),arguments.items,(self_.projection_quantifiers.len-1-owner_index) as u32,ordinal as u32); let __cleanup_result_12_0: Id = accept(work,id,err); arguments.deinit(); return __cleanup_result_12_0; }
   }
  }
  if work.failure!=blot_error::Error.none { let __cleanup_result_13_0: Id = 0; arguments.deinit(); return __cleanup_result_13_0; } if !work.resolver.enabled { let __cleanup_result_14_0: Id = reject(work,blot_error::Error.unresolved_type); arguments.deinit(); return __cleanup_result_14_0; }
  let id,err=work.resolver.context.resolve(Identity {n.a,n.b},source.projectionMember(n),arguments.items); let __cleanup_result_15_0: Id = accept(work,id,err); arguments.deinit(); return __cleanup_result_15_0;
  arguments.deinit(); }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider {
  let child=projectDepth(work,n.a,depth+1,budget,retained,memo,height); var result_tag=Tag.array;
  if tag==blot_check_types::Tag.list { result_tag=Tag.list; } else if tag==blot_check_types::Tag.cursor { result_tag=Tag.cursor; } else if tag==blot_check_types::Tag.resolver { result_tag=Tag.resolver; } else if tag==blot_check_types::Tag.provider { result_tag=Tag.provider; }
  var row: u32=0; if result_tag==Tag.provider { row=projectRowDepth(work,n.c,depth+1,budget,retained,memo,height); } if work.failure!=blot_error::Error.none { return 0; }
  let id,err=internWithEffects(self_,result_tag,child,0,row,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.state_provider||tag==blot_check_types::Tag.function {
  let a=projectDepth(work,n.a,depth+1,budget,retained,memo,height); let b=projectDepth(work,n.b,depth+1,budget,retained,memo,height); var c: u32=0;
  if tag==blot_check_types::Tag.function { c=projectRowDepth(work,n.c,depth+1,budget,retained,memo,height); } else { c=projectDepth(work,n.c,depth+1,budget,retained,memo,height); }
  if work.failure!=blot_error::Error.none { return 0; } var result_tag=Tag.function; if tag==blot_check_types::Tag.state_provider { result_tag=Tag.state_provider; } let id,err=internWithEffects(self_,result_tag,a,b,c,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.type_constructor { let id,err=intern(self_,Tag.type_constructor,n.a,n.b,[]); return accept(work,id,err); }
 var values=WordBuffer {};  var result_tag=Tag.product; var a: u32=0; var b: u32=0;
 if tag==blot_check_types::Tag.record { result_tag=Tag.record; for index in 0..n.b { let field=source.recordField(n,index); values.push(field.name); values.push(projectDepth(work,field.ty,depth+1,budget,retained,memo,height)); } }
 else if tag==blot_check_types::Tag.nominal { result_tag=Tag.nominal; a=n.a; b=n.b; for child in source.nominalArguments(n) { values.push(projectDepth(work,child,depth+1,budget,retained,memo,height)); } }
 else { for child in source.list(blot_check_types::List {n.a,n.b}) { values.push(projectDepth(work,child,depth+1,budget,retained,memo,height)); } }
 if work.failure!=blot_error::Error.none { let __cleanup_result_16_0: Id = 0; values.deinit(); return __cleanup_result_16_0; } let id,err=intern(self_,result_tag,a,b,values.items); let __cleanup_result_17_0: Id = accept(work,id,err); values.deinit(); return __cleanup_result_17_0;
 values.deinit(); }
recursive fn projectRowBody<S,R>(work: ProjectionWork<S,R>&,row: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,height: u16&) -> u32 {
 let self_=work.destination; let source=work.source; var suffix: u32=0; var formal: Id=0;
 match source.row(row).tail {
  closed=>{},
  formal leaf=>{
   let key,err=blot_check_types::formalRowKey(leaf.value); if err!=blot_error::Error.none { return reject(work,blot_error::Error.unresolved_type); } var replaced=false;
   for mapping in mappingItems(work.rows) { if mapping.variable==key { if mapping.evidence>=self_.effects.rows.len { return reject(work,blot_error::Error.type_mismatch); } suffix=mapping.evidence; replaced=true; break; } }
   if !replaced { formal=projectDepth(work,leaf.value,depth+1,budget,retained,memo,height); if work.failure!=blot_error::Error.none { return 0; } let projected=node(self_,formal); if projected.tag!=Tag.bound||projected.b!=1 { return reject(work,blot_error::Error.type_mismatch); } }
  },
  parameter=>{ return reject(work,blot_error::Error.unresolved_type); },
  variable v=>{ var found=false; for mapping in mappingItems(work.rows) { if mapping.variable==v.value { if mapping.evidence>=self_.effects.rows.len { return reject(work,blot_error::Error.type_mismatch); } suffix=mapping.evidence; found=true; break; } } if !found { return reject(work,blot_error::Error.unresolved_type); } },
 }
 var labels=WordBuffer {};  var arguments=WordBuffer {};
 for label in source.rowLabels(row) {
  if work.resolver.enabled { if work.resolver.remaining==0 { let __cleanup_result_18_0: u32 = reject(work,blot_error::Error.evidence_limit); arguments.deinit(); labels.deinit(); return __cleanup_result_18_0; } work.resolver.remaining--; }
  if retained&&memo!=null { let answer=blot_reuse_projection_cache::get(memo.labels,label); if answer!=null { let a=answer; if depth+a.height>1024||budget<a.visits { let __cleanup_result_19_0: u32 = reject(work,blot_error::Error.evidence_limit); arguments.deinit(); labels.deinit(); return __cleanup_result_19_0; } budget-=a.visits; if height<a.height { height=a.height; } labels.push(a.value); continue; } }
  let operation=source.operation(label); let instance=blot_check_types::selectionAtom(source,operation.instance); if instance.unit==0&&instance.decl!=0 { let __cleanup_result_20_0: u32 = reject(work,blot_error::Error.unresolved_type); arguments.deinit(); labels.deinit(); return __cleanup_result_20_0; }
  arguments.resize(0); let before=budget; var label_height: u16=0;
  for argument in source.operationArguments(label) { if retained { arguments.push(projectDepth(work,argument,depth+1,budget,retained,memo,label_height)); } else { arguments.push(projectDepth(work,argument,depth+1,budget,retained,memo,height)); } }
  if work.failure!=blot_error::Error.none { let __cleanup_result_21_0: u32 = 0; arguments.deinit(); labels.deinit(); return __cleanup_result_21_0; } let projected,err=self_.effects.internOperationInstance(operation.identity,arguments.items,instance); if err!=blot_error::Error.none { let __cleanup_result_22_0: u32 = reject(work,err); arguments.deinit(); labels.deinit(); return __cleanup_result_22_0; }
  if retained&&memo!=null { if height<label_height { height=label_height; } blot_reuse_projection_cache::insert(memo.labels,label,blot_reuse_projection_cache::Answer {projected,(before-budget) as u32,label_height}); } labels.push(projected);
 }
 labels.append(self_.effects.view().rowLabels(suffix)); if suffix!=0 { formal=self_.effects.rows.items[suffix].formal; } let result,err=self_.effects.internRowWithFormal(labels.items,formal); let __cleanup_result_23_0: u32 = accept(work,result,err); arguments.deinit(); labels.deinit(); return __cleanup_result_23_0;
 arguments.deinit(); labels.deinit(); }
fn project<S>(self_: Store,source: const S&,ty: u32,mappings: const Mapping[:]) -> Id,Error { return projectWithRows(self_,source,ty,mappings,[]); }
fn projectWithRows<S>(self_: Store,source: const S&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:]) -> Id,Error { var budget: i64=1000000; return projectWithBudget(self_,source,ty,mappings,rows,budget); }
fn projectWithBudget<S>(self_: Store,source: const S&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:],budget: i64&) -> Id,Error {
 var no=NoResolver {}; let remaining: i64& =no_projection_remaining; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=ProjectionWork<S,NoResolver> {self_,source,mappings,rows,resolver}; let id=projectDepth(work,ty,0,budget,false,null,null); return id,work.failure;
}
fn projectSelected<S,R>(self_: Store,source: const S&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:],resolver: ProjectionResolver<R>&) -> Id,Error {
 var budget: i64=1000000; let initialized,cache_error=blot_reuse_projection_cache::initPooled(); if cache_error!=blot_error::Error.none { return 0,cache_error; } var memo=initialized;  var work=ProjectionWork<S,R> {self_,source,mappings,rows,resolver}; let id=projectDepth(work,ty,0,budget,false,memo,null); let __cleanup_result_1_0: Id = id; let __cleanup_result_1_1: Error = work.failure; memo.deinit(); return __cleanup_result_1_0, __cleanup_result_1_1;
 memo.deinit(); }
fn projectEffects<S>(self_: Store,source: const S&,row: u32,mappings: const Mapping[:],rows: const RowMapping[:]) -> u32,Error {
 var no=NoResolver {}; let remaining: i64& =no_projection_remaining; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=ProjectionWork<S,NoResolver> {self_,source,mappings,rows,resolver}; var budget: i64=1000000; let id=projectRowDepth(work,row,0,budget,false,null,null); return id,work.failure;
}
fn projectOwned(self_: Store,source: const blot_check_types::Store&,ty: u32,memo: blot_reuse_projection_cache::Cache&) -> Id,Error {
 if !memo.activate(source.owner_id,self_.owner_id,source.closed_generation,source.effects.physical_epoch) { return project(self_,source,ty,[]); }
 var no=NoResolver {}; let remaining: i64& =no_projection_remaining; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=ProjectionWork<blot_check_types::Store,NoResolver> {self_,source,[],[],resolver}; var budget: i64=1000000; let id=projectDepth(work,ty,0,budget,true,memo,null); return id,work.failure;
}
fn projectAssociatedOwned(self_: Store,source: const blot_check_types::Store&,ty: u32,memo: blot_reuse_projection_cache::Cache&,remaining: i64&) -> Id,Error {
 var no=NoResolver {}; var resolver=ProjectionResolver<NoResolver> {no,remaining,true}; if !memo.activate(source.owner_id,self_.owner_id,source.closed_generation,source.effects.physical_epoch) { return projectSelected(self_,source,ty,[],[],resolver); }
 var work=ProjectionWork<blot_check_types::Store,NoResolver> {self_,source,[],[],resolver}; var budget: i64=1000000; let id=projectDepth(work,ty,0,budget,false,memo,null); return id,work.failure;
}
struct MatchWork<S,R,M,B> { destination: Store,source: S,mappings: M,rows: B,has_rows: bool,resolver: ProjectionResolver<R>,memo: MatchMemo,use_memo: bool,failure: Error=blot_error::Error.none }
fn matchFail<S,R,M,B>(work: MatchWork<S,R,M,B>&,error: Error) -> bool { if work.failure==blot_error::Error.none { work.failure=error; } return false; }
fn matchDepth<S,R,M,B>(work: MatchWork<S,R,M,B>&,pattern: u32,actual: Id,depth: i64,budget: i64&) -> bool {
 if work.failure!=blot_error::Error.none { return false; } if depth>=1024||(work.use_memo&&depth>=256)||budget==0 { return matchFail(work,blot_error::Error.evidence_limit); } budget--;
 let self_=work.destination; let source=work.source; if actual==0||actual>=self_.nodes.len { return matchFail(work,blot_error::Error.unresolved_type); }
 let pair=(pattern as u64)<<32|actual; if work.use_memo&&work.memo.contains(pair) { return true; } let n=source.node(pattern); let tag=n.tag;
 if tag==blot_check_types::Tag.projection {
  if !work.resolver.enabled { return false; } let normalized,err=projectSelected(self_,source,pattern,mappingItems(work.mappings),mappingItems(work.rows),work.resolver);
  if err==blot_error::Error.unresolved_type { return false; } if err!=blot_error::Error.none { return matchFail(work,err); } if normalized!=actual { return false; } if work.use_memo { work.memo.insert(pair,true); } return true;
 }
 let concrete=node(self_,actual);
 if tag==blot_check_types::Tag.existential||(tag==blot_check_types::Tag.forall&&concrete.tag==Tag.forall) {
  var wanted=Tag.existential; if tag==blot_check_types::Tag.forall { wanted=Tag.forall; } if concrete.tag!=wanted||n.c!=concrete.b { return false; }
  let expected,err=projectWithRows(self_,source,pattern,mappingItems(work.mappings),mappingItems(work.rows)); if err==blot_error::Error.unresolved_type { return false; } if err!=blot_error::Error.none { return matchFail(work,err); } return expected==actual;
 }
 if tag==blot_check_types::Tag.never||concrete.tag==Tag.never { return true; }
 if tag==blot_check_types::Tag.forall { return matchDepth(work,n.a,actual,depth+1,budget); }
 if tag==blot_check_types::Tag.variable||(tag==blot_check_types::Tag.bound&&n.b==0) {
  if concrete.tag==Tag.erased_proof { return false; } for mapping in mappingItems(work.mappings) { if mapping.variable==pattern { return mapping.evidence==actual; } } work.mappings.push(Mapping {pattern,actual}); if mappingFailure(work.mappings)!=blot_error::Error.none { return matchFail(work,mappingFailure(work.mappings)); } return true;
 }
 var same=false;
 if tag==blot_check_types::Tag.scoped { same=concrete.tag==Tag.scoped&&(n.b==0||(n.b==concrete.b&&n.c==concrete.c)); }
 else if tag==blot_check_types::Tag.usage { same=concrete.tag==Tag.usage&&n.b==concrete.b; }
 else if tag==blot_check_types::Tag.erased_proof { same=concrete.tag==Tag.erased_proof; }
 else if tag==blot_check_types::Tag.unit { same=concrete.tag==Tag.unit; } else if tag==blot_check_types::Tag.boolean { same=concrete.tag==Tag.boolean; }
 else if tag==blot_check_types::Tag.unsigned32 { same=concrete.tag==Tag.unsigned32; } else if tag==blot_check_types::Tag.floating32 { same=concrete.tag==Tag.floating32; }
 else if tag==blot_check_types::Tag.array { same=concrete.tag==Tag.array; } else if tag==blot_check_types::Tag.list { same=concrete.tag==Tag.list; }
 else if tag==blot_check_types::Tag.cursor { same=concrete.tag==Tag.cursor; } else if tag==blot_check_types::Tag.resolver { same=concrete.tag==Tag.resolver; }
 else if tag==blot_check_types::Tag.provider { same=concrete.tag==Tag.provider; } else if tag==blot_check_types::Tag.state_provider { same=concrete.tag==Tag.state_provider; }
 else if tag==blot_check_types::Tag.type_constructor { same=concrete.tag==Tag.type_constructor&&n.a==concrete.a&&n.b==concrete.b; }
 else if tag==blot_check_types::Tag.function { same=concrete.tag==Tag.function; } else if tag==blot_check_types::Tag.product { same=concrete.tag==Tag.product; }
 else if tag==blot_check_types::Tag.record { same=concrete.tag==Tag.record; } else if tag==blot_check_types::Tag.nominal { same=concrete.tag==Tag.nominal&&n.a==concrete.a&&n.b==concrete.b; }
 if !same { return false; }
 if tag==blot_check_types::Tag.provider&&!matchRowDepth(work,n.c,concrete.c,depth+1,budget) { return false; }
 if tag==blot_check_types::Tag.scoped {
  if !matchDepth(work,n.a,concrete.a,depth+1,budget) { return false; }
  if n.b==0 {
   let owner=source.head(n.c,0); if source.node(owner).tag==blot_check_types::Tag.variable {
    var known=false; for mapping in mappingItems(work.mappings) { if mapping.variable==owner { let prior=node(self_,mapping.evidence); if prior.tag!=Tag.scoped||prior.b!=concrete.b||prior.c!=concrete.c { return false; } known=true; break; } }
    if !known { work.mappings.push(Mapping {owner,actual}); if mappingFailure(work.mappings)!=blot_error::Error.none { return matchFail(work,mappingFailure(work.mappings)); } }
   } else { let atom=blot_check_types::selectionAtom(source,Identity {0,owner}); if atom.unit!=concrete.b||atom.decl!=concrete.c { return false; } }
  }
 } else if tag==blot_check_types::Tag.usage||tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider { if !matchDepth(work,n.a,concrete.a,depth+1,budget) { return false; } }
 else if tag==blot_check_types::Tag.state_provider { if !matchDepth(work,n.a,concrete.a,depth+1,budget)||!matchDepth(work,n.b,concrete.b,depth+1,budget)||!matchDepth(work,n.c,concrete.c,depth+1,budget) { return false; } }
 else if tag==blot_check_types::Tag.function { if !matchDepth(work,n.a,concrete.a,depth+1,budget)||!matchRowDepth(work,n.c,concrete.c,depth+1,budget)||!matchDepth(work,n.b,concrete.b,depth+1,budget) { return false; } }
 else if tag==blot_check_types::Tag.product||tag==blot_check_types::Tag.nominal {
  var expected=source.list(blot_check_types::List {n.a,n.b}); if tag==blot_check_types::Tag.nominal { expected=source.nominalArguments(n); }
  var actuals=WordBuffer {};  actuals.append(children(self_,actual)); if expected.len!=actuals.len { let __cleanup_result_24_0: bool = false; actuals.deinit(); return __cleanup_result_24_0; }
  for child,index in expected { if !matchDepth(work,child,actuals.items[index],depth+1,budget) { let __cleanup_result_25_0: bool = false; actuals.deinit(); return __cleanup_result_25_0; } }
  actuals.deinit(); } else if tag==blot_check_types::Tag.record {
  var fields=WordBuffer {};  fields.append(children(self_,actual)); if fields.len!=(n.b as i64)*2 { let __cleanup_result_26_0: bool = false; fields.deinit(); return __cleanup_result_26_0; }
  for index in 0..n.b { let field=source.recordField(n,index); var found=false; var i=0; while i<fields.len { if fields.items[i]==field.name { if !matchDepth(work,field.ty,fields.items[i+1],depth+1,budget) { let __cleanup_result_27_0: bool = false; fields.deinit(); return __cleanup_result_27_0; } found=true; break; } i+=2; } if !found { let __cleanup_result_28_0: bool = false; fields.deinit(); return __cleanup_result_28_0; } }
  fields.deinit(); }
 if work.use_memo { work.memo.insert(pair,true); } return true;
}
fn matchRowDepth<S,R,M,B>(work: MatchWork<S,R,M,B>&,pattern: u32,actual: u32,depth: i64,budget: i64&) -> bool {
 if work.failure!=blot_error::Error.none { return false; } let self_=work.destination; let source=work.source; let tail=source.row(pattern).tail; var closed=false;
 match tail {
  parameter=>{ return matchFail(work,blot_error::Error.unresolved_type); },
  variable=>{ if !work.has_rows { return matchFail(work,blot_error::Error.unresolved_type); } },
  formal=>{
   var projection=ProjectionWork<S,R> {self_,source,mappingItems(work.mappings),mappingItems(work.rows),work.resolver}; let expected=projectRowDepth(projection,pattern,depth+1,budget,false,null,null); if projection.failure!=blot_error::Error.none { return matchFail(work,projection.failure); } return actual==expected;
  },
  closed=>{ closed=true; },
 }
 let actual_formal=self_.effects.rows.items[actual].formal; if closed&&actual_formal!=0 { return false; }
 let expected=source.rowLabels(pattern); var actuals=WordBuffer {};  actuals.append(self_.effects.view().rowLabels(actual));
 if expected.len>actuals.len||(closed&&expected.len!=actuals.len) { let __cleanup_result_29_0: bool = false; actuals.deinit(); return __cleanup_result_29_0; } var used=BoolBuffer {};  used.resize(actuals.len,false);
 let __cleanup_result_30_0: bool = matchOperations(work,expected,actuals.items,used.items,tail,actual_formal,0,depth,budget); used.deinit(); actuals.deinit(); return __cleanup_result_30_0;
 used.deinit(); actuals.deinit(); }
fn matchOperations<S,R,M,B>(work: MatchWork<S,R,M,B>&,expected: const u32[:],actuals: const u32[:],used: bool[:],tail: blot_check_effects::Tail,actual_formal: Id,index: i64,depth: i64,budget: i64&) -> bool {
 if work.failure!=blot_error::Error.none { return false; } if depth>=1024||(work.use_memo&&depth>=256)||budget==0 { return matchFail(work,blot_error::Error.evidence_limit); } budget--;
 let self_=work.destination; let source=work.source;
 if index==expected.len {
  match tail {
   closed=>{ return true; },
   variable variable=>{
    var remaining=WordBuffer {};  for label,i in actuals { if !used[i] { remaining.push(label); } }
    let suffix,err=self_.effects.internRowWithFormal(remaining.items,actual_formal); if err!=blot_error::Error.none { let __cleanup_result_31_0: bool = matchFail(work,err); remaining.deinit(); return __cleanup_result_31_0; }
    for mapping in mappingItems(work.rows) { if mapping.variable==variable.value { let __cleanup_result_32_0: bool = mapping.evidence==suffix; remaining.deinit(); return __cleanup_result_32_0; } } work.rows.push(RowMapping {variable.value,suffix}); if mappingFailure(work.rows)!=blot_error::Error.none { return matchFail(work,mappingFailure(work.rows)); } let __cleanup_result_33_0: bool = true; remaining.deinit(); return __cleanup_result_33_0;
    remaining.deinit(); },
   _=>{ return matchFail(work,blot_error::Error.unresolved_type); },
  }
 }
 let operation=source.operation(expected[index]); let arguments=source.operationArguments(expected[index]);
 for label,i in actuals {
  if work.use_memo { if budget==0 { return matchFail(work,blot_error::Error.evidence_limit); } budget--; } if used[i] { continue; }
  let concrete=self_.effects.view().operation(label); let atom=blot_check_types::selectionAtom(source,operation.instance);
  if atom!=concrete.instance||operation.identity.unit!=concrete.identity.unit||operation.identity.decl!=concrete.identity.decl { continue; }
  var actual_arguments=WordBuffer {};  actual_arguments.append(self_.effects.view().operationArguments(label)); if arguments.len!=actual_arguments.len { actual_arguments.deinit(); continue; }
  let frontier=work.mappings.len; let row_frontier=work.rows.len; var same=true;
  for argument,j in arguments { if !matchDepth(work,argument,actual_arguments.items[j],depth+1,budget) { same=false; break; } }
  if work.failure!=blot_error::Error.none { let __cleanup_result_35_0: bool = false; actual_arguments.deinit(); return __cleanup_result_35_0; }
  if same { used[i]=true; if matchOperations(work,expected,actuals,used,tail,actual_formal,index+1,depth+1,budget) { let __cleanup_result_36_0: bool = true; actual_arguments.deinit(); return __cleanup_result_36_0; } used[i]=false; }
  if work.failure!=blot_error::Error.none { let __cleanup_result_37_0: bool = false; actual_arguments.deinit(); return __cleanup_result_37_0; } if work.use_memo { work.memo.clear(); } work.mappings.resize(frontier); work.rows.resize(row_frontier);
  actual_arguments.deinit(); }
 return false;
}
fn matchWithRowsBudgetInner<S,M,B>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,budget: i64&) -> bool,Error {
 var no=NoResolver {}; let remaining: i64& =no_projection_remaining; var resolver=ProjectionResolver<NoResolver> {no,remaining,false};  var work=MatchWork<S,NoResolver,M,B> {self_,source,mappings,rows,true,resolver,MatchMemo {},true};  let frontier=mappings.len; let row_frontier=rows.len;
 let accepted=matchDepth(work,pattern,actual,0,budget); if !accepted||work.failure!=blot_error::Error.none { mappings.resize(frontier); rows.resize(row_frontier); } let __cleanup_result_38_0: bool = accepted; let __cleanup_result_38_1: Error = work.failure; work.memo.deinit(); return __cleanup_result_38_0, __cleanup_result_38_1;
 work.memo.deinit(); }
fn matchWithRowsInner<S,M,B>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B) -> bool,Error {
 var no=NoResolver {}; let remaining: i64& =no_projection_remaining; var resolver=ProjectionResolver<NoResolver> {no,remaining,false};  var work=MatchWork<S,NoResolver,M,B> {self_,source,mappings,rows,true,resolver,MatchMemo {},false};  var budget: i64=1000000; let frontier=mappings.len; let row_frontier=rows.len;
 let accepted=matchDepth(work,pattern,actual,0,budget); if !accepted||work.failure!=blot_error::Error.none { mappings.resize(frontier); rows.resize(row_frontier); } let __cleanup_result_39_0: bool = accepted; let __cleanup_result_39_1: Error = work.failure; work.memo.deinit(); return __cleanup_result_39_0, __cleanup_result_39_1;
 work.memo.deinit(); }
fn match_<S>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&) -> bool,Error {
 var rows=PooledRows {};  let activated=activate(rows); if activated!=blot_error::Error.none { let __cleanup_result_40_0: bool = false; let __cleanup_result_40_1: Error = activated; rows.deinit(); return __cleanup_result_40_0, __cleanup_result_40_1; } var no=NoResolver {}; let remaining: i64& =no_projection_remaining; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=MatchWork<S,NoResolver,Mapping[>..<]&,PooledRows> {self_,source,mappings,rows,false,resolver,MatchMemo {},false};  var budget: i64=1000000; let frontier=mappings.len;
 let accepted=matchDepth(work,pattern,actual,0,budget); if !accepted||work.failure!=blot_error::Error.none { mappings.resize(frontier); } let __cleanup_result_41_0: bool = accepted; let __cleanup_result_41_1: Error = work.failure; work.memo.deinit(); rows.deinit(); return __cleanup_result_41_0, __cleanup_result_41_1;
 work.memo.deinit(); rows.deinit(); }
fn matchSelectedInner<S,R,M,B>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> bool,Error {
  var work=MatchWork<S,R,M,B> {self_,source,mappings,rows,true,resolver,MatchMemo {},true};  let frontier=mappings.len; let row_frontier=rows.len; let accepted=matchDepth(work,pattern,actual,0,resolver.remaining); if !accepted||work.failure!=blot_error::Error.none { mappings.resize(frontier); rows.resize(row_frontier); } let __cleanup_result_42_0: bool = accepted; let __cleanup_result_42_1: Error = work.failure; work.memo.deinit(); return __cleanup_result_42_0, __cleanup_result_42_1;
 work.memo.deinit(); }
fn matchSignatureInner<S,R,M,B>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&,infer_rows: bool) -> bool,Error {
  var work=MatchWork<S,R,M,B> {self_,source,mappings,rows,true,resolver,MatchMemo {},true};  let frontier=mappings.len; let row_frontier=rows.len; var accepted=false;

 var expected=pattern; var supplied=actual; var depth=0;
 while source.node(expected).tag==blot_check_types::Tag.forall { if depth>=128 { let __cleanup_result_90_0: bool = false; let __cleanup_result_90_1: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_43_0: bool = __cleanup_result_90_0; let __cleanup_result_43_1: Error = __cleanup_result_90_1; work.memo.deinit(); return __cleanup_result_43_0, __cleanup_result_43_1; } depth++; expected=source.node(expected).a; }
 while source.node(expected).tag==blot_check_types::Tag.function {
  if depth>=256||resolver.remaining==0 { let __cleanup_result_91_0: bool = false; let __cleanup_result_91_1: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_44_0: bool = __cleanup_result_91_0; let __cleanup_result_44_1: Error = __cleanup_result_91_1; work.memo.deinit(); return __cleanup_result_44_0, __cleanup_result_44_1; } resolver.remaining--; let arrow=source.node(expected); let concrete=node(self_,supplied); if concrete.tag!=Tag.function { let __cleanup_result_92_0: bool = false; let __cleanup_result_92_1: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_45_0: bool = __cleanup_result_92_0; let __cleanup_result_45_1: Error = __cleanup_result_92_1; work.memo.deinit(); return __cleanup_result_45_0, __cleanup_result_45_1; }
  if !matchDepth(work,arrow.a,concrete.a,depth+1,resolver.remaining) { let __cleanup_result_93_0: bool = false; let __cleanup_result_93_1: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_46_0: bool = __cleanup_result_93_0; let __cleanup_result_46_1: Error = __cleanup_result_93_1; work.memo.deinit(); return __cleanup_result_46_0, __cleanup_result_46_1; }
  var projection=ProjectionWork<S,R> {self_,source,mappingItems(mappings),mappingItems(rows),resolver}; var required_row=projectRowDepth(projection,arrow.c,depth+1,resolver.remaining,false,null,null);
  if projection.failure==blot_error::Error.unresolved_type {
   if !infer_rows { let __cleanup_result_94_0: bool = false; let __cleanup_result_94_1: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_47_0: bool = __cleanup_result_94_0; let __cleanup_result_47_1: Error = __cleanup_result_94_1; work.memo.deinit(); return __cleanup_result_47_0, __cleanup_result_47_1; } if !matchRowDepth(work,arrow.c,concrete.c,depth+1,resolver.remaining) { let __cleanup_result_95_0: bool = false; let __cleanup_result_95_1: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_48_0: bool = __cleanup_result_95_0; let __cleanup_result_48_1: Error = __cleanup_result_95_1; work.memo.deinit(); return __cleanup_result_48_0, __cleanup_result_48_1; }
   projection.failure=blot_error::Error.none; projection.mappings=mappingItems(mappings); projection.rows=mappingItems(rows); required_row=projectRowDepth(projection,arrow.c,depth+1,resolver.remaining,false,null,null);
  }
  if projection.failure!=blot_error::Error.none { let __cleanup_result_96_0: bool = false; let __cleanup_result_96_1: Error = projection.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_49_0: bool = __cleanup_result_96_0; let __cleanup_result_49_1: Error = __cleanup_result_96_1; work.memo.deinit(); return __cleanup_result_49_0, __cleanup_result_49_1; }
  var required=WordBuffer {};  required.append(self_.effects.view().rowLabels(required_row));
  for label in required.items { if resolver.remaining==0 { let __cleanup_result_97_0: bool = false; let __cleanup_result_97_1: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_50_0: bool = __cleanup_result_97_0; let __cleanup_result_50_1: Error = __cleanup_result_97_1; required.deinit(); work.memo.deinit(); return __cleanup_result_50_0, __cleanup_result_50_1; } resolver.remaining--; var found=false; for actual in self_.effects.view().rowLabels(concrete.c) { if actual==label { found=true; break; } } if !found { let __cleanup_result_98_0: bool = false; let __cleanup_result_98_1: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_51_0: bool = __cleanup_result_98_0; let __cleanup_result_51_1: Error = __cleanup_result_98_1; required.deinit(); work.memo.deinit(); return __cleanup_result_51_0, __cleanup_result_51_1; } }
  expected=arrow.b; supplied=concrete.b; depth++;
  required.deinit(); }
 accepted=matchDepth(work,expected,supplied,depth+1,resolver.remaining); let __cleanup_result_99_0: bool = accepted; let __cleanup_result_99_1: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_52_0: bool = __cleanup_result_99_0; let __cleanup_result_52_1: Error = __cleanup_result_99_1; work.memo.deinit(); return __cleanup_result_52_0, __cleanup_result_52_1;
 { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } }  work.memo.deinit(); }
fn matchTemplateInner<S,R,M,B>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> bool,Error { return matchSignatureInner<S,R,M,B>(self_,source,pattern,actual,mappings,rows,resolver,false); }
fn matchLegacySignatureInner<S,R,M,B>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> bool,Error { return matchSignatureInner<S,R,M,B>(self_,source,pattern,actual,mappings,rows,resolver,true); }
fn matchPrerequisiteInner<S,R,M,B>(self_: Store,source: const S&,pattern: u32,operands: Id[4],arity: i64,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> Id,bool,Error {
  var work=MatchWork<S,R,M,B> {self_,source,mappings,rows,true,resolver,MatchMemo {},true};  var labels=WordBuffer {};  let frontier=mappings.len; let row_frontier=rows.len; var accepted=false;

 var required=pattern; var requested: u32=0;
 if operands[3]!=0 { let carrier=node(self_,operands[3]); if carrier.tag!=Tag.function { let __cleanup_result_100_0: Id = 0; let __cleanup_result_100_1: bool = false; let __cleanup_result_100_2: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_53_0: Id = __cleanup_result_100_0; let __cleanup_result_53_1: bool = __cleanup_result_100_1; let __cleanup_result_53_2: Error = __cleanup_result_100_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_53_0, __cleanup_result_53_1, __cleanup_result_53_2; } requested=carrier.c; }
 for stage in 0..arity {
  if resolver.remaining==0 { let __cleanup_result_101_0: Id = 0; let __cleanup_result_101_1: bool = false; let __cleanup_result_101_2: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_54_0: Id = __cleanup_result_101_0; let __cleanup_result_54_1: bool = __cleanup_result_101_1; let __cleanup_result_54_2: Error = __cleanup_result_101_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_54_0, __cleanup_result_54_1, __cleanup_result_54_2; } resolver.remaining--; let arrow=source.node(required); if arrow.tag!=blot_check_types::Tag.function { let __cleanup_result_102_0: Id = 0; let __cleanup_result_102_1: bool = false; let __cleanup_result_102_2: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_55_0: Id = __cleanup_result_102_0; let __cleanup_result_55_1: bool = __cleanup_result_102_1; let __cleanup_result_55_2: Error = __cleanup_result_102_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_55_0, __cleanup_result_55_1, __cleanup_result_55_2; }
  if !matchDepth(work,arrow.a,operands[stage],0,resolver.remaining) { let __cleanup_result_103_0: Id = 0; let __cleanup_result_103_1: bool = false; let __cleanup_result_103_2: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_56_0: Id = __cleanup_result_103_0; let __cleanup_result_56_1: bool = __cleanup_result_103_1; let __cleanup_result_56_2: Error = __cleanup_result_103_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_56_0, __cleanup_result_56_1, __cleanup_result_56_2; }
  var projection=ProjectionWork<S,R> {self_,source,mappingItems(mappings),mappingItems(rows),resolver}; var own_row=projectRowDepth(projection,arrow.c,0,resolver.remaining,false,null,null);
  if projection.failure==blot_error::Error.unresolved_type {
   if operands[3]==0 { let __cleanup_result_104_0: Id = 0; let __cleanup_result_104_1: bool = false; let __cleanup_result_104_2: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_57_0: Id = __cleanup_result_104_0; let __cleanup_result_57_1: bool = __cleanup_result_104_1; let __cleanup_result_57_2: Error = __cleanup_result_104_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_57_0, __cleanup_result_57_1, __cleanup_result_57_2; } if !matchRowDepth(work,arrow.c,requested,0,resolver.remaining) { let __cleanup_result_105_0: Id = 0; let __cleanup_result_105_1: bool = false; let __cleanup_result_105_2: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_58_0: Id = __cleanup_result_105_0; let __cleanup_result_58_1: bool = __cleanup_result_105_1; let __cleanup_result_58_2: Error = __cleanup_result_105_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_58_0, __cleanup_result_58_1, __cleanup_result_58_2; }
   projection.failure=blot_error::Error.none; projection.mappings=mappingItems(mappings); projection.rows=mappingItems(rows); own_row=projectRowDepth(projection,arrow.c,0,resolver.remaining,false,null,null);
  }
  if projection.failure!=blot_error::Error.none { let __cleanup_result_106_0: Id = 0; let __cleanup_result_106_1: bool = false; let __cleanup_result_106_2: Error = projection.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_59_0: Id = __cleanup_result_106_0; let __cleanup_result_59_1: bool = __cleanup_result_106_1; let __cleanup_result_59_2: Error = __cleanup_result_106_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_59_0, __cleanup_result_59_1, __cleanup_result_59_2; }
  let own_labels=self_.effects.view().rowLabels(own_row);
  for label,index in own_labels {
   if resolver.remaining==0 { let __cleanup_result_107_0: Id = 0; let __cleanup_result_107_1: bool = false; let __cleanup_result_107_2: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_60_0: Id = __cleanup_result_107_0; let __cleanup_result_60_1: bool = __cleanup_result_107_1; let __cleanup_result_60_2: Error = __cleanup_result_107_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_60_0, __cleanup_result_60_1, __cleanup_result_60_2; } resolver.remaining--; var count=0;
   for earlier in own_labels[..index+1] { if resolver.remaining==0 { let __cleanup_result_108_0: Id = 0; let __cleanup_result_108_1: bool = false; let __cleanup_result_108_2: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_61_0: Id = __cleanup_result_108_0; let __cleanup_result_61_1: bool = __cleanup_result_108_1; let __cleanup_result_61_2: Error = __cleanup_result_108_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_61_0, __cleanup_result_61_1, __cleanup_result_61_2; } resolver.remaining--; if earlier==label { count++; } }
   if operands[3]!=0 { var available=0; for actual in self_.effects.view().rowLabels(requested) { if resolver.remaining==0 { let __cleanup_result_109_0: Id = 0; let __cleanup_result_109_1: bool = false; let __cleanup_result_109_2: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_62_0: Id = __cleanup_result_109_0; let __cleanup_result_62_1: bool = __cleanup_result_109_1; let __cleanup_result_62_2: Error = __cleanup_result_109_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_62_0, __cleanup_result_62_1, __cleanup_result_62_2; } resolver.remaining--; if actual==label { available++; } } if count>available { let __cleanup_result_110_0: Id = 0; let __cleanup_result_110_1: bool = false; let __cleanup_result_110_2: Error = blot_error::Error.type_mismatch; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_63_0: Id = __cleanup_result_110_0; let __cleanup_result_63_1: bool = __cleanup_result_110_1; let __cleanup_result_63_2: Error = __cleanup_result_110_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_63_0, __cleanup_result_63_1, __cleanup_result_63_2; } }
   var present=0; for actual in labels.items { if resolver.remaining==0 { let __cleanup_result_111_0: Id = 0; let __cleanup_result_111_1: bool = false; let __cleanup_result_111_2: Error = blot_error::Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_64_0: Id = __cleanup_result_111_0; let __cleanup_result_64_1: bool = __cleanup_result_111_1; let __cleanup_result_64_2: Error = __cleanup_result_111_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_64_0, __cleanup_result_64_1, __cleanup_result_64_2; } resolver.remaining--; if actual==label { present++; } } if count>present { labels.push(label); }
  }
  required=arrow.b;
 }
 if !matchDepth(work,required,operands[2],0,resolver.remaining) { if work.failure!=blot_error::Error.none { let __cleanup_result_112_0: Id = 0; let __cleanup_result_112_1: bool = false; let __cleanup_result_112_2: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_65_0: Id = __cleanup_result_112_0; let __cleanup_result_65_1: bool = __cleanup_result_112_1; let __cleanup_result_65_2: Error = __cleanup_result_112_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_65_0, __cleanup_result_65_1, __cleanup_result_65_2; } let __cleanup_result_113_0: Id = 0; let __cleanup_result_113_1: bool = false; let __cleanup_result_113_2: Error = blot_error::Error.type_mismatch; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_66_0: Id = __cleanup_result_113_0; let __cleanup_result_66_1: bool = __cleanup_result_113_1; let __cleanup_result_66_2: Error = __cleanup_result_113_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_66_0, __cleanup_result_66_1, __cleanup_result_66_2; }
 accepted=true; if operands[3]!=0 { let __cleanup_result_114_0: Id = operands[3]; let __cleanup_result_114_1: bool = true; let __cleanup_result_114_2: Error = blot_error::Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_67_0: Id = __cleanup_result_114_0; let __cleanup_result_67_1: bool = __cleanup_result_114_1; let __cleanup_result_67_2: Error = __cleanup_result_114_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_67_0, __cleanup_result_67_1, __cleanup_result_67_2; }
 let own,err=self_.effects.internRow(labels.items); if err!=blot_error::Error.none { let __cleanup_result_115_0: Id = 0; let __cleanup_result_115_1: bool = false; let __cleanup_result_115_2: Error = err; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_68_0: Id = __cleanup_result_115_0; let __cleanup_result_68_1: bool = __cleanup_result_115_1; let __cleanup_result_68_2: Error = __cleanup_result_115_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_68_0, __cleanup_result_68_1, __cleanup_result_68_2; } let id,error=internWithEffects(self_,Tag.function,1,1,own,[]); let __cleanup_result_116_0: Id = id; let __cleanup_result_116_1: bool = error==blot_error::Error.none; let __cleanup_result_116_2: Error = error; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_69_0: Id = __cleanup_result_116_0; let __cleanup_result_69_1: bool = __cleanup_result_116_1; let __cleanup_result_69_2: Error = __cleanup_result_116_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_69_0, __cleanup_result_69_1, __cleanup_result_69_2;
 { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } }  labels.deinit(); work.memo.deinit(); }
struct SnapshotTables { nodes: Node[>..]&,extra: Id[>..]&,quantifier_goals: QuantifierGoals[>..]&,quantifier_obligations: Goal[>..]&,effects: blot_check_effect_evidence::SnapshotTables }
fn copyOwned(self_: const Store&,target: SnapshotTables) -> Snapshot,Error {
 let ns=target.nodes.len; let es=target.extra.len; let gs=target.quantifier_goals.len; let os=target.quantifier_obligations.len;
 target.nodes.append(self_.nodes.items); target.extra.append(self_.extra.items); target.quantifier_goals.append(self_.quantifier_goals.items); target.quantifier_obligations.append(self_.quantifier_obligations.items);
 let effects,err=self_.effects.copyOwned(target.effects); if err!=blot_error::Error.none { return default<Snapshot>(),err; }
 return Snapshot {nodes:target.nodes[ns..],extra:target.extra[es..],effects:effects,quantifier_goals:target.quantifier_goals[gs..],quantifier_obligations:target.quantifier_obligations[os..]},blot_error::Error.none;
}
fn clone(self_: const Store&,destination: Store&) -> Error {
 if self_.owner_id==destination.owner_id||!valid(self_)||!valid(destination) { return blot_error::Error.type_mismatch; }
 destination.nodes.clear(); destination.nodes.append(self_.nodes.items);
 destination.extra.clear(); destination.extra.append(self_.extra.items);
 destination.next.clear(); destination.next.append(self_.next.items);
 destination.quantifier_goals.clear(); destination.quantifier_goals.append(self_.quantifier_goals.items);
 destination.quantifier_obligations.clear(); destination.quantifier_obligations.append(self_.quantifier_obligations.items);
 destination.projection_owners.clear(); destination.projection_quantifiers.clear(); copyBuckets(destination.buckets,self_.buckets);
 let effects,error=blot_check_effect_evidence::clone(self_.effects); if error!=blot_error::Error.none { return error; } destination.effects.deinit(); destination.effects=effects; return blot_error::Error.none;
}
fn withStore<C,F>(context: C&) -> Error { let initialized,error=init(); if error!=blot_error::Error.none { return error; } var store=initialized; let result=F(context,store); deinit(store); return result; }
fn withPooledStore<C,F>(context: C&) -> Error { return withStore<C>(context,F); }
fn withStoreValue<C,R,F>(context: C&) -> R,Error { let initialized,error=init(); if error!=blot_error::Error.none { return default<R>(),error; } var store=initialized; let result,failure=F(context,store); deinit(store); return result,failure; }
fn withPooledStoreValue<C,R,F>(context: C&) -> R,Error { return withStoreValue<C,R>(context,F); }
fn deinit(self_: Store&) { if self_.lease==0 { return; } assert(valid(self_));
 self_.nodes.deinit();
 self_.extra.deinit();
 self_.next.deinit();
 self_.buckets.deinit();
 self_.projection_owners.deinit();
 self_.projection_quantifiers.deinit();
 self_.quantifier_goals.deinit();
 self_.quantifier_obligations.deinit();
 self_.effects.deinit(); let index=self_.lease-1; states[index].owner_id=0; states.free(index); self_=Store {};
}
fn prepareCommit(source: const Store&,destination: Store&) -> Error { if !valid(source)||!valid(destination)||source.owner_id==destination.owner_id { return blot_error::Error.type_mismatch; }
 if source.nodes.failure!=blot_error::Error.none { return source.nodes.failure; }
 if source.extra.failure!=blot_error::Error.none { return source.extra.failure; }
 if source.next.failure!=blot_error::Error.none { return source.next.failure; }
 if source.projection_owners.failure!=blot_error::Error.none { return source.projection_owners.failure; }
 if source.projection_quantifiers.failure!=blot_error::Error.none { return source.projection_quantifiers.failure; }
 if source.quantifier_goals.failure!=blot_error::Error.none { return source.quantifier_goals.failure; }
 if source.quantifier_obligations.failure!=blot_error::Error.none { return source.quantifier_obligations.failure; }
 return blot_check_effect_evidence::prepareCommit(source.effects,destination.effects); }
// Publication moves typed capacity runs; old destination storage is reclaimed.
fn commit(source: Store&,destination: Store&) { assert(valid(source)&&valid(destination)&&source.owner_id!=destination.owner_id);
 destination.nodes.deinit(); destination.nodes.items=source.nodes; source.nodes=NodeBuffer {};
 destination.extra.deinit(); destination.extra.items=source.extra; source.extra=WordBuffer {};
 destination.next.deinit(); destination.next=source.next; source.next=WordBuffer {};
 destination.buckets.deinit(); destination.buckets=source.buckets; source.buckets=Buckets {};
 destination.projection_owners.deinit(); destination.projection_owners=source.projection_owners; source.projection_owners=OwnersBuffer {};
 destination.projection_quantifiers.deinit(); destination.projection_quantifiers=source.projection_quantifiers; source.projection_quantifiers=WordBuffer {};
 destination.quantifier_goals.deinit(); destination.quantifier_goals.items=source.quantifier_goals; source.quantifier_goals=QuantifierBuffer {};
 destination.quantifier_obligations.deinit(); destination.quantifier_obligations.items=source.quantifier_obligations; source.quantifier_obligations=GoalBuffer {};
 blot_check_effect_evidence::commit(source.effects,destination.effects); let identity=destination.owner_id; destination.owner_id=source.owner_id; states[destination.lease-1].owner_id=destination.owner_id; source.owner_id=identity; states[source.lease-1].owner_id=source.owner_id;
}

struct ByteBuffer { storage: u8[:]=default<u8[:]>(),items: u8[:]=default<u8[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ByteBuffer: u8[>..]=[];
fn ensure(self_: ByteBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ByteBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ByteBuffer&,value: u8) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ByteBuffer); self_.len=self_.items.len; }
fn append(self_: ByteBuffer&,values: const u8[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ByteBuffer); self_.len=self_.items.len; }
fn resize(self_: ByteBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ByteBuffer&,length: i64,value: u8) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ByteBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ByteBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ByteBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct BoolBuffer { storage: bool[:]=default<bool[:]>(),items: bool[:]=default<bool[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_BoolBuffer: bool[>..]=[];
fn ensure(self_: BoolBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_BoolBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: BoolBuffer&,value: bool) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_BoolBuffer); self_.len=self_.items.len; }
fn append(self_: BoolBuffer&,values: const bool[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_BoolBuffer); self_.len=self_.items.len; }
fn resize(self_: BoolBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: BoolBuffer&,length: i64,value: bool) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: BoolBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: BoolBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_BoolBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct MappingBuffer { storage: Mapping[:]=default<Mapping[:]>(),items: Mapping[:]=default<Mapping[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_MappingBuffer: Mapping[>..]=[];
fn ensure(self_: MappingBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_MappingBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: MappingBuffer&,value: Mapping) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_MappingBuffer); self_.len=self_.items.len; }
fn append(self_: MappingBuffer&,values: const Mapping[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_MappingBuffer); self_.len=self_.items.len; }
fn resize(self_: MappingBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: MappingBuffer&,length: i64,value: Mapping) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: MappingBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: MappingBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_MappingBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RowMappingBuffer { storage: RowMapping[:]=default<RowMapping[:]>(),items: RowMapping[:]=default<RowMapping[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RowMappingBuffer: RowMapping[>..]=[];
fn ensure(self_: RowMappingBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RowMappingBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RowMappingBuffer&,value: RowMapping) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RowMappingBuffer); self_.len=self_.items.len; }
fn append(self_: RowMappingBuffer&,values: const RowMapping[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RowMappingBuffer); self_.len=self_.items.len; }
fn resize(self_: RowMappingBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: RowMappingBuffer&,length: i64,value: RowMapping) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: RowMappingBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RowMappingBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RowMappingBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct PooledMappingsHeader { buffer: MappingBuffer=MappingBuffer {},generation: u64=0,live: bool=false }
reusable var mapping_headers: PooledMappingsHeader[>..]=[];
var inactive_mapping_header: MappingBuffer=MappingBuffer {};
var next_mapping_generation: u64=1;
struct PooledMappings { header: MappingBuffer& =inactive_mapping_header,items: (Mapping[:])& =inactive_mapping_header.items,len: i64& =inactive_mapping_header.len,failure: Error& =inactive_mapping_header.failure,lease: u32=0,generation: u64=0 }
fn activate(self_: PooledMappings&) -> Error { if self_.lease!=0 { assert(self_.lease-1<mapping_headers.len&&mapping_headers[self_.lease-1].live&&mapping_headers[self_.lease-1].generation==self_.generation); return blot_error::Error.none; } if next_mapping_generation==0xffffffffffffffff||mapping_headers.len>=0xffffffff { return blot_error::Error.out_of_memory; } let generation=next_mapping_generation; next_mapping_generation++; let index=mapping_headers.alloc_index(PooledMappingsHeader {generation:generation,live:true}); let header: MappingBuffer& =mapping_headers[index].buffer; self_.header .= header; self_.items .= header.items; self_.len .= header.len; self_.failure .= header.failure; self_.lease=(index+1) as u32; self_.generation=generation; return blot_error::Error.none; }
fn push(self_: PooledMappings&,value: Mapping) { let error=activate(self_); if error!=blot_error::Error.none { self_.failure=error; return; } self_.header.push(value); }
fn append(self_: PooledMappings&,values: const Mapping[:]) { let error=activate(self_); if error!=blot_error::Error.none { self_.failure=error; return; } self_.header.append(values); }
fn resize(self_: PooledMappings&,length: i64) { assert(self_.lease!=0||length==0); if self_.lease!=0 { self_.header.resize(length); } }
fn clear(self_: PooledMappings&) { if self_.lease!=0 { self_.header.clear(); } }
fn deinit(self_: PooledMappings&) { if self_.lease==0 { return; } let error=activate(self_); assert(error==blot_error::Error.none); self_.header.deinit(); let index=self_.lease-1; mapping_headers[index].live=false; mapping_headers.free(index); self_=PooledMappings {}; }
fn mappingItems(self_: PooledMappings) -> const Mapping[:] { return self_.items; }
struct PooledRowsHeader { buffer: RowMappingBuffer=RowMappingBuffer {},generation: u64=0,live: bool=false }
reusable var row_mapping_headers: PooledRowsHeader[>..]=[];
var inactive_row_mapping_header: RowMappingBuffer=RowMappingBuffer {};
var next_row_mapping_generation: u64=1;
struct PooledRows { header: RowMappingBuffer& =inactive_row_mapping_header,items: (RowMapping[:])& =inactive_row_mapping_header.items,len: i64& =inactive_row_mapping_header.len,failure: Error& =inactive_row_mapping_header.failure,lease: u32=0,generation: u64=0 }
fn activate(self_: PooledRows&) -> Error { if self_.lease!=0 { assert(self_.lease-1<row_mapping_headers.len&&row_mapping_headers[self_.lease-1].live&&row_mapping_headers[self_.lease-1].generation==self_.generation); return blot_error::Error.none; } if next_row_mapping_generation==0xffffffffffffffff||row_mapping_headers.len>=0xffffffff { return blot_error::Error.out_of_memory; } let generation=next_row_mapping_generation; next_row_mapping_generation++; let index=row_mapping_headers.alloc_index(PooledRowsHeader {generation:generation,live:true}); let header: RowMappingBuffer& =row_mapping_headers[index].buffer; self_.header .= header; self_.items .= header.items; self_.len .= header.len; self_.failure .= header.failure; self_.lease=(index+1) as u32; self_.generation=generation; return blot_error::Error.none; }
fn push(self_: PooledRows&,value: RowMapping) { let error=activate(self_); if error!=blot_error::Error.none { self_.failure=error; return; } self_.header.push(value); }
fn append(self_: PooledRows&,values: const RowMapping[:]) { let error=activate(self_); if error!=blot_error::Error.none { self_.failure=error; return; } self_.header.append(values); }
fn resize(self_: PooledRows&,length: i64) { assert(self_.lease!=0||length==0); if self_.lease!=0 { self_.header.resize(length); } }
fn clear(self_: PooledRows&) { if self_.lease!=0 { self_.header.clear(); } }
fn deinit(self_: PooledRows&) { if self_.lease==0 { return; } let error=activate(self_); assert(error==blot_error::Error.none); self_.header.deinit(); let index=self_.lease-1; row_mapping_headers[index].live=false; row_mapping_headers.free(index); self_=PooledRows {}; }
fn mappingItems(self_: PooledRows) -> const RowMapping[:] { return self_.items; }
type MatchMemo=blot_support_pooled_map::Map<u64,bool>;
reusable[] var match_memo_slots: dictionary_slot<u64,bool>[>..]=[];
fn contains(self_: const MatchMemo&,key: u64) -> bool { return blot_support_pooled_map::contains(self_,key); }
fn insert(self_: MatchMemo&,key: u64,value: bool) { blot_support_pooled_map::insert(self_,key,value,match_memo_slots); }
fn clear(self_: MatchMemo&) { blot_support_pooled_map::clear(self_); }
fn deinit(self_: MatchMemo&) { blot_support_pooled_map::deinit(self_,match_memo_slots); }
fn mappingItems(self_: const Mapping[:]) -> const Mapping[:] { return self_; }
fn mappingItems(self_: const RowMapping[:]) -> const RowMapping[:] { return self_; }
fn mappingItems(self_: Mapping[>..<]&) -> const Mapping[:] { return self_; }
fn mappingItems(self_: RowMapping[>..<]&) -> const RowMapping[:] { return self_; }

fn matchWithRowsBudget<S>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,budget: i64&) -> bool,Error { return matchWithRowsBudgetInner<S,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, actual, mappings, rows, budget); }
fn matchWithRowsBudget<S>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,budget: i64&) -> bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return false,first; } let second=activate(rows); if second!=blot_error::Error.none { return false,second; } return matchWithRowsBudgetInner<S,PooledMappings,PooledRows>(self_, source, pattern, actual, mappings, rows, budget); }
fn matchWithRows<S>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&) -> bool,Error { return matchWithRowsInner<S,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, actual, mappings, rows); }
fn matchWithRows<S>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&) -> bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return false,first; } let second=activate(rows); if second!=blot_error::Error.none { return false,second; } return matchWithRowsInner<S,PooledMappings,PooledRows>(self_, source, pattern, actual, mappings, rows); }
fn matchSelected<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> bool,Error { return matchSelectedInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, actual, mappings, rows, resolver); }
fn matchSelected<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return false,first; } let second=activate(rows); if second!=blot_error::Error.none { return false,second; } return matchSelectedInner<S,R,PooledMappings,PooledRows>(self_, source, pattern, actual, mappings, rows, resolver); }
fn matchSignature<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&,infer_rows: bool) -> bool,Error { return matchSignatureInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, actual, mappings, rows, resolver, infer_rows); }
fn matchSignature<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&,infer_rows: bool) -> bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return false,first; } let second=activate(rows); if second!=blot_error::Error.none { return false,second; } return matchSignatureInner<S,R,PooledMappings,PooledRows>(self_, source, pattern, actual, mappings, rows, resolver, infer_rows); }
fn matchTemplate<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> bool,Error { return matchTemplateInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, actual, mappings, rows, resolver); }
fn matchTemplate<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return false,first; } let second=activate(rows); if second!=blot_error::Error.none { return false,second; } return matchTemplateInner<S,R,PooledMappings,PooledRows>(self_, source, pattern, actual, mappings, rows, resolver); }
fn matchLegacySignature<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> bool,Error { return matchLegacySignatureInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, actual, mappings, rows, resolver); }
fn matchLegacySignature<S,R>(self_: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return false,first; } let second=activate(rows); if second!=blot_error::Error.none { return false,second; } return matchLegacySignatureInner<S,R,PooledMappings,PooledRows>(self_, source, pattern, actual, mappings, rows, resolver); }
fn matchPrerequisite<S,R>(self_: Store,source: const S&,pattern: u32,operands: Id[4],arity: i64,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> Id,bool,Error { return matchPrerequisiteInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self_, source, pattern, operands, arity, mappings, rows, resolver); }
fn matchPrerequisite<S,R>(self_: Store,source: const S&,pattern: u32,operands: Id[4],arity: i64,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> Id,bool,Error { let first=activate(mappings); if first!=blot_error::Error.none { return 0,false,first; } let second=activate(rows); if second!=blot_error::Error.none { return 0,false,second; } return matchPrerequisiteInner<S,R,PooledMappings,PooledRows>(self_, source, pattern, operands, arity, mappings, rows, resolver); }

fn mappingFailure(self_: Mapping[>..<]&) -> Error { return blot_error::Error.none; }
fn mappingFailure(self_: RowMapping[>..<]&) -> Error { return blot_error::Error.none; }
fn mappingFailure(self_: PooledMappings) -> Error { return self_.failure; }
fn mappingFailure(self_: PooledRows) -> Error { return self_.failure; }

var no_projection_remaining: i64=0;
