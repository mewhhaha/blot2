// Interned semantic types. Exact owner-local evidence; never a machine layout.
namespace blot_eval_type_evidence;
import dictionary;
import support.pooled_buffer;
import support.pooled_map;
import check.types;
import check.effects;
import check.effect_evidence;
import reuse.projection_cache;
import .evidence_projection;
import parse.symbols;
import support.error;
import support.option;
import support.native;
type Id=u32;
type Error=blot_error::Error;
type Identity=blot_check_types::NominalIdentity;
enum Tag { absent,unit,boolean,unsigned32,floating32,never,function,product,record,nominal,array,list,cursor,type_constructor,resolver,provider,state_provider,erased_proof,bound,usage,scoped,forall,existential,projection }
fn tagCode(tag: Tag) -> u8 {
 match tag {
  absent=>0,unit=>1,boolean=>2,unsigned32=>3,floating32=>4,never=>5,function=>6,product=>7,record=>8,nominal=>9,array=>10,list=>11,cursor=>12,type_constructor=>13,resolver=>14,provider=>15,state_provider=>16,erased_proof=>17,bound=>20,usage=>21,scoped=>23,forall=>24,existential=>25,projection=>26,
 }
}
fn tagFromCode(code: u8) -> Tag,bool {
 if code==0 { return Tag.absent,true; } if code==1 { return Tag.unit,true; } if code==2 { return Tag.boolean,true; } if code==3 { return Tag.unsigned32,true; } if code==4 { return Tag.floating32,true; } if code==5 { return Tag.never,true; } if code==6 { return Tag.function,true; } if code==7 { return Tag.product,true; } if code==8 { return Tag.record,true; } if code==9 { return Tag.nominal,true; } if code==10 { return Tag.array,true; } if code==11 { return Tag.list,true; } if code==12 { return Tag.cursor,true; } if code==13 { return Tag.type_constructor,true; } if code==14 { return Tag.resolver,true; } if code==15 { return Tag.provider,true; } if code==16 { return Tag.state_provider,true; } if code==17 { return Tag.erased_proof,true; } if code==20 { return Tag.bound,true; } if code==21 { return Tag.usage,true; } if code==23 { return Tag.scoped,true; } if code==24 { return Tag.forall,true; } if code==25 { return Tag.existential,true; } if code==26 { return Tag.projection,true; } return Tag.absent,false;
}
struct Node { tag: Tag,a: u32=0,b: u32=0,c: u32=0 }
struct Mapping { variable: u32,evidence: Id }
struct RowMapping { variable: u32,evidence: u32 }
struct Goal { ty: Id,kind: blot_check_types::ObligationKind,name: u32=0,result: Id=0,other: Id=0,signature: Id=0,operator: blot_check_types::Operator=blot_check_types::Operator.none,identity: Identity=Identity {0,0},explicit: bool=false }
struct QuantifierGoals { owner: Id,goals: blot_check_types::List }
struct Projection { member: u32,scope: u32,goal: u32 }
struct ScopeFrame { binders: const Id[:],goals: const Goal[:]=[] }
struct ProjectionResolver<R> { context: R&,remaining: i64&,enabled: bool=true }
struct NoResolver {}
fn resolve(self: NoResolver&,identity: Identity,member: u32,arguments: const Id[:]) -> Id,Error { return 0,Error.unresolved_type; }
struct View { owner_id: u64=0,nodes: const Node[:],extra: const Id[:],effects: blot_check_effect_evidence::View,quantifier_goals: const QuantifierGoals[:]=[],quantifier_obligations: const Goal[:]=[] }
fn quantifierGoals(self: View,owner: Id) -> const Goal[:] {
 var lo=0; var hi=self.quantifier_goals.len;
 while lo<hi { let mid=lo+(hi-lo)/2; if self.quantifier_goals[mid].owner<owner { lo=mid+1; } else { hi=mid; } }
 if lo<self.quantifier_goals.len { let entry=self.quantifier_goals[lo]; if entry.owner==owner { return self.quantifier_obligations[entry.goals.start..entry.goals.start+entry.goals.len]; } } return self.quantifier_obligations[..0];
}
fn validateGoalTables(self: View) -> Error { var remaining: i64=65536; return validateGoalTablesWithBudget(self,remaining); }
fn validateGoalTablesWithBudget(self: View,remaining: i64&) -> Error {
 if self.quantifier_goals.len>self.nodes.len||self.quantifier_obligations.len>65536 { return Error.evidence_limit; }
 var previous: Id=0; var cursor=0;
 for entry in self.quantifier_goals {
  if remaining==0 { return Error.evidence_limit; } remaining--;
  if entry.owner<=previous||entry.owner>=self.nodes.len||entry.goals.len==0||entry.goals.start!=cursor||cursor>self.quantifier_obligations.len||entry.goals.len>self.quantifier_obligations.len-cursor { return Error.type_mismatch; }
  let tag=self.node(entry.owner).tag; if tag!=Tag.forall&&tag!=Tag.existential { return Error.type_mismatch; }
  for goal in self.quantifier_obligations[entry.goals.start..entry.goals.start+entry.goals.len] {
   if remaining==0 { return Error.evidence_limit; } remaining--;
   if blot_check_types::obligationKindCode(goal.kind)>blot_check_types::obligationKindCode(blot_check_types::ObligationKind.task_receive)||blot_check_types::operatorCode(goal.operator)>blot_check_types::operatorCode(blot_check_types::Operator.shift_right)||goal.ty==0 { return Error.type_mismatch; }
   if goal.ty>=entry.owner||goal.other>=entry.owner||goal.result>=entry.owner||goal.signature>=entry.owner { return Error.type_mismatch; }
  }
  previous=entry.owner; cursor+=entry.goals.len;
 }
 if cursor!=self.quantifier_obligations.len { return Error.type_mismatch; } return Error.none;
}
fn node(self: View,id: Id) -> Node { return self.nodes[id]; }
fn children(self: View,id: Id) -> const Id[:] {
 let n=node(self,id);
 if n.tag==Tag.product { return self.extra[n.a..n.a+n.b]; }
 if n.tag==Tag.record { return self.extra[n.a..n.a+(n.b as i64)*2]; }
 if n.tag==Tag.nominal||n.tag==Tag.projection { return self.extra[n.c+1..n.c+1+self.extra[n.c]]; }
 if n.tag==Tag.forall||n.tag==Tag.existential { return self.extra[n.c..n.c+n.b]; }
 return self.extra[..0];
}
fn projection(self: View,id: Id) -> Projection { let n=node(self,id); let start=n.c+1+self.extra[n.c]; return Projection {self.extra[start],self.extra[start+1],self.extra[start+2]}; }
fn binderList(self: View,binders: const Id[:],seen: bool[:],remaining: i64&) -> Error {
 if binders.len==0||binders.len>128 { return Error.type_mismatch; }
 for id,ordinal in binders {
  if remaining==0 { return Error.evidence_limit; } remaining--; if id==0||id>=self.nodes.len { return Error.type_mismatch; }
  let leaf=node(self,id); if leaf.tag!=Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { return Error.type_mismatch; }
  if seen.len!=0 { if id>=seen.len { return Error.evidence_limit; } seen[id]=true; }
 }
 return Error.none;
}
fn walk(self: View,id: Id,depth: i64,remaining: i64&,frames: ScopeFrame[:],scope_count: i64,region: bool,seen: bool[:],open: bool) -> Error {
 if depth>=128||remaining==0 { return Error.evidence_limit; } remaining--; if id==0||id>=self.nodes.len { return Error.type_mismatch; }
 let n=node(self,id); if region&&(n.tag!=Tag.bound||n.b!=2) { return Error.type_mismatch; }
 if n.tag==Tag.bound {
  if n.c>=scope_count { if !open||n.a>=128||n.b>2||(region&&n.b!=2)||(!region&&n.b!=0) { return Error.type_mismatch; } return Error.none; }
  let owner=frames[scope_count-1-n.c].binders; if n.a>=owner.len { return Error.type_mismatch; } let formal=node(self,owner[n.a]);
  if formal.b!=n.b||(region&&n.b!=2)||(!region&&n.b!=0) { return Error.type_mismatch; }
  if seen.len!=0 { if id>=seen.len { return Error.evidence_limit; } seen[id]=true; } return Error.none;
 }
 if n.tag==Tag.forall||n.tag==Tag.existential {
  if scope_count==frames.len||n.c>self.extra.len||n.b>self.extra.len-n.c { return Error.type_mismatch; } let binders=children(self,id);
  let err=binderList(self,binders,seen,remaining); if err!=Error.none { return err; }
  if n.tag==Tag.existential { for binder in binders { if node(self,binder).b!=0 { return Error.type_mismatch; } } }
  frames[scope_count]=ScopeFrame {binders,quantifierGoals(self,id)}; let error=walk(self,n.a,depth+1,remaining,frames,scope_count+1,false,seen,open); if error!=Error.none { return error; }
  for goal in quantifierGoals(self,id) { if remaining==0 { return Error.evidence_limit; } remaining--; let endpoints: Id[4]=[goal.ty,goal.other,goal.result,goal.signature]; for endpoint in endpoints { if endpoint!=0 { let e=walk(self,endpoint,depth+1,remaining,frames,scope_count+1,false,seen,open); if e!=Error.none { return e; } } } } return Error.none;
 }
 if n.tag==Tag.projection {
  if n.c>=self.extra.len||self.extra[n.c]>self.extra.len-n.c-1 { return Error.type_mismatch; } let count=self.extra[n.c]; if self.extra.len-n.c-1-count<3 { return Error.type_mismatch; } let descriptor=projection(self,id);
  if descriptor.member==0||descriptor.scope>=128||descriptor.goal>=4096 { return Error.type_mismatch; }
  for arg in children(self,id) { let err=walk(self,arg,depth+1,remaining,frames,scope_count,false,seen,open); if err!=Error.none { return err; } }
  if descriptor.scope>=scope_count { if !open { return Error.type_mismatch; } return Error.none; }
  let goals=frames[scope_count-1-descriptor.scope].goals; if descriptor.goal>=goals.len { return Error.type_mismatch; }
  let err=blot_eval_evidence_projection::validate(self,id,goals[descriptor.goal],remaining); if err!=Error.none { return err; }
  if seen.len!=0 { if id>=seen.len { return Error.evidence_limit; } seen[id]=true; } return Error.none;
 }
 if n.tag==Tag.usage {
  if n.b>7 { return Error.type_mismatch; } let loan=n.b==2||n.b==3; if loan!=(n.c!=0) { return Error.type_mismatch; }
  let err=walk(self,n.a,depth+1,remaining,frames,scope_count,false,seen,open); if err!=Error.none { return err; } if loan { return walk(self,n.c,depth+1,remaining,frames,scope_count,true,seen,open); } return Error.none;
 }
 if n.tag==Tag.function||n.tag==Tag.state_provider {
  let a=walk(self,n.a,depth+1,remaining,frames,scope_count,false,seen,open); if a!=Error.none { return a; } let b=walk(self,n.b,depth+1,remaining,frames,scope_count,false,seen,open); if b!=Error.none { return b; }
  if n.tag==Tag.function { return walkRow(self,n.c,depth+1,remaining,frames,scope_count,seen,open); } return walk(self,n.c,depth+1,remaining,frames,scope_count,false,seen,open);
 }
 if n.tag==Tag.provider { let e=walk(self,n.a,depth+1,remaining,frames,scope_count,false,seen,open); if e!=Error.none { return e; } return walkRow(self,n.c,depth+1,remaining,frames,scope_count,seen,open); }
 if n.tag==Tag.array||n.tag==Tag.list||n.tag==Tag.cursor||n.tag==Tag.resolver { return walk(self,n.a,depth+1,remaining,frames,scope_count,false,seen,open); }
 if n.tag==Tag.product||n.tag==Tag.record||n.tag==Tag.nominal {
  var start=n.a as i64; var count=n.b as i64;
  if n.tag==Tag.record { if count>0x7fffffff { return Error.evidence_limit; } count*=2; }
  if n.tag==Tag.nominal { if n.c>=self.extra.len { return Error.type_mismatch; } start=n.c+1; count=self.extra[n.c]; }
  if start>self.extra.len||count>self.extra.len-start { return Error.type_mismatch; }
  for child,index in self.extra[start..start+count] { if n.tag==Tag.record&&index%2==0 { continue; } let err=walk(self,child,depth+1,remaining,frames,scope_count,false,seen,open); if err!=Error.none { return err; } } return Error.none;
 }
 if n.tag==Tag.scoped||n.tag==Tag.absent||n.tag==Tag.erased_proof { return Error.unresolved_type; } return Error.none;
}
fn walkRow(self: View,row: u32,depth: i64,remaining: i64&,frames: ScopeFrame[:],scope_count: i64,seen: bool[:],open: bool) -> Error {
 if row==0 { return Error.none; } if depth>=128||remaining==0||row>=self.effects.rows.len { return Error.evidence_limit; } remaining--;
 let formal=self.effects.rows[row].formal;
 if formal!=0 {
  if formal>=self.nodes.len||remaining==0 { return Error.type_mismatch; } remaining--; let leaf=node(self,formal);
  if leaf.tag!=Tag.bound||leaf.b!=1||leaf.a>=128||leaf.c>=128 { return Error.type_mismatch; }
  if leaf.c>=scope_count { if !open { return Error.type_mismatch; } }
  else { let owner=frames[scope_count-1-leaf.c].binders; if leaf.a>=owner.len||node(self,owner[leaf.a]).b!=1 { return Error.type_mismatch; } }
  if seen.len!=0 { if formal>=seen.len { return Error.evidence_limit; } seen[formal]=true; }
 }
 for label in self.effects.rowLabels(row) { if label==0||label>=self.effects.operations.len||remaining==0 { return Error.type_mismatch; } remaining--; for arg in self.effects.operationArguments(label) { let err=walk(self,arg,depth+1,remaining,frames,scope_count,false,seen,open); if err!=Error.none { return err; } } } return Error.none;
}
fn openQuantifier(self: View,id: Id,remaining: i64&,seen: bool[:]) -> Error { let e=validateGoalTablesWithBudget(self,remaining); if e!=Error.none { return e; } return openQuantifierValidated(self,id,remaining,seen); }
fn openQuantifierValidated(self: View,id: Id,remaining: i64&,seen: bool[:]) -> Error { var frames: ScopeFrame[128]; return walk(self,id,0,remaining,frames,0,false,seen,true); }
fn body(self: View,id: Id,binders: const Id[:],depth: i64,remaining: i64&,seen: bool[:]) -> Error { let e=validateGoalTablesWithBudget(self,remaining); if e!=Error.none { return e; } var frames: ScopeFrame[128]; let error=binderList(self,binders,seen,remaining); if error!=Error.none { return error; } frames[0]=ScopeFrame {binders,[]}; return walk(self,id,depth,remaining,frames,1,false,seen,false); }
fn bodyWithGoalsValidated(self: View,id: Id,binders: const Id[:],goals: const Goal[:],remaining: i64&,seen: bool[:]) -> Error { var frames: ScopeFrame[128]; let err=binderList(self,binders,seen,remaining); if err!=Error.none { return err; } frames[0]=ScopeFrame {binders,goals}; return walk(self,id,0,remaining,frames,1,false,seen,true); }
fn openBodyWithGoals(self: View,id: Id,binders: const Id[:],goals: const Goal[:],remaining: i64&,seen: bool[:]) -> Error { let err=validateGoalTablesWithBudget(self,remaining); if err!=Error.none { return err; } return bodyWithGoalsValidated(self,id,binders,goals,remaining,seen); }
fn openBody(self: View,id: Id,binders: const Id[:],remaining: i64&,seen: bool[:]) -> Error { return openBodyWithGoals(self,id,binders,[],remaining,seen); }
fn closed(self: View,id: Id,depth: i64,remaining: i64&) -> Error { let err=validateGoalTablesWithBudget(self,remaining); if err!=Error.none { return err; } var frames: ScopeFrame[128]; return walk(self,id,depth,remaining,frames,0,false,[],false); }
struct Snapshot { owner_id: u64=blot_native::fresh_owner_id(),nodes: const Node[:],extra: const Id[:],effects: blot_check_effect_evidence::Snapshot,quantifier_goals: const QuantifierGoals[:]=[],quantifier_obligations: const Goal[:]=[] }
fn view(self: const Snapshot&) -> View { return View {self.owner_id,self.nodes,self.extra,self.effects.view(),self.quantifier_goals,self.quantifier_obligations}; }
struct NodeBuffer { storage: Node[:]=[],items: Node[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_NodeBuffer: Node[>..]=[];
fn ensure(self: NodeBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_NodeBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: NodeBuffer&,value: Node) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_NodeBuffer); self.len=self.items.len; }
fn append(self: NodeBuffer&,values: const Node[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_NodeBuffer); self.len=self.items.len; }
fn resize(self: NodeBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: NodeBuffer&,length: i64,value: Node) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: NodeBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: NodeBuffer&) { blot_support_pooled_buffer::deinit(self,pool_NodeBuffer); self.len=0; self.failure=Error.none; }
struct WordBuffer { storage: u32[:]=[],items: u32[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_WordBuffer: u32[>..]=[];
fn ensure(self: WordBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_WordBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: WordBuffer&,value: u32) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_WordBuffer); self.len=self.items.len; }
fn append(self: WordBuffer&,values: const u32[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_WordBuffer); self.len=self.items.len; }
fn resize(self: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: WordBuffer&,length: i64,value: u32) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: WordBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self,pool_WordBuffer); self.len=0; self.failure=Error.none; }
struct OwnersBuffer { storage: (const u32[:])[:]=[],items: (const u32[:])[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_OwnersBuffer: (const u32[:])[>..]=[];
fn ensure(self: OwnersBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_OwnersBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: OwnersBuffer&,value: (const u32[:])) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_OwnersBuffer); self.len=self.items.len; }
fn append(self: OwnersBuffer&,values: const (const u32[:])[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_OwnersBuffer); self.len=self.items.len; }
fn resize(self: OwnersBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: OwnersBuffer&,length: i64,value: (const u32[:])) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: OwnersBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: OwnersBuffer&) { blot_support_pooled_buffer::deinit(self,pool_OwnersBuffer); self.len=0; self.failure=Error.none; }
struct QuantifierBuffer { storage: QuantifierGoals[:]=[],items: QuantifierGoals[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_QuantifierBuffer: QuantifierGoals[>..]=[];
fn ensure(self: QuantifierBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_QuantifierBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: QuantifierBuffer&,value: QuantifierGoals) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_QuantifierBuffer); self.len=self.items.len; }
fn append(self: QuantifierBuffer&,values: const QuantifierGoals[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_QuantifierBuffer); self.len=self.items.len; }
fn resize(self: QuantifierBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: QuantifierBuffer&,length: i64,value: QuantifierGoals) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: QuantifierBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: QuantifierBuffer&) { blot_support_pooled_buffer::deinit(self,pool_QuantifierBuffer); self.len=0; self.failure=Error.none; }
struct GoalBuffer { storage: Goal[:]=[],items: Goal[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_GoalBuffer: Goal[>..]=[];
fn ensure(self: GoalBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_GoalBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: GoalBuffer&,value: Goal) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_GoalBuffer); self.len=self.items.len; }
fn append(self: GoalBuffer&,values: const Goal[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_GoalBuffer); self.len=self.items.len; }
fn resize(self: GoalBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: GoalBuffer&,length: i64,value: Goal) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: GoalBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: GoalBuffer&) { blot_support_pooled_buffer::deinit(self,pool_GoalBuffer); self.len=0; self.failure=Error.none; }
type Buckets=blot_support_pooled_map::Map<u64,u32>;
reusable[] var bucket_slots: dictionary_slot<u64,u32>[>..]=[];
fn get(self: const Buckets&,key: u64) -> u32? { return blot_support_pooled_map::get(self,key); }
fn insert(self: Buckets&,key: u64,value: u32) { blot_support_pooled_map::insert(self,key,value,bucket_slots); }
fn clear(self: Buckets&) { blot_support_pooled_map::clear(self); }
fn deinit(self: Buckets&) { blot_support_pooled_map::deinit(self,bucket_slots); }
fn reserve(self: Buckets&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return Error.out_of_memory; } var capacity=max(8,self.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self.slots.len { blot_support_pooled_map::grow(self,capacity,bucket_slots); } return Error.none; }
fn copyBuckets(destination: Buckets&,source: const Buckets&) { if destination.slots.len!=0 { bucket_slots.free_slice(destination.slots); } destination.slots=[]; destination.count=source.count; if source.slots.len!=0 { destination.slots=bucket_slots.alloc_slice(source.slots.len); for slot,index in source.slots { destination.slots[index]=slot; } } }
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
struct Store { owner_id: u64=0,lease: u32=0,generation: u64=0,effects: blot_check_effect_evidence::Store&=inactive_effects,nodes: NodeBuffer&=inactive_NodeBuffer,extra: WordBuffer&=inactive_WordBuffer,next: WordBuffer&=inactive_WordBuffer,buckets: Buckets&=inactive_Buckets,projection_owners: OwnersBuffer&=inactive_OwnersBuffer,projection_quantifiers: WordBuffer&=inactive_WordBuffer,quantifier_goals: QuantifierBuffer&=inactive_QuantifierBuffer,quantifier_obligations: GoalBuffer&=inactive_GoalBuffer }
fn valid(self: const Store&) -> bool { return self.lease!=0&&self.lease-1<states.len&&states[self.lease-1].owner_id==self.owner_id&&states[self.lease-1].generation==self.generation&&self.owner_id!=0; }
fn init() -> Store,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Store {},Error.out_of_memory; } let effects,error=blot_check_effect_evidence::init(); if error!=Error.none { return Store {},error; } let generation=next_generation; next_generation++; let owner=blot_native::fresh_owner_id(); let index=states.alloc_index(State {owner_id:owner,generation:generation,effects:effects}); let state: State&=states[index]; var self=Store {owner_id:owner,lease:(index+1) as u32,generation:generation,effects:state.effects,nodes:state.nodes,extra:state.extra,next:state.next,buckets:state.buckets,projection_owners:state.projection_owners,projection_quantifiers:state.projection_quantifiers,quantifier_goals:state.quantifier_goals,quantifier_obligations:state.quantifier_obligations}; for tag in [Tag.absent,Tag.unit,Tag.boolean,Tag.unsigned32,Tag.floating32,Tag.never] { self.nodes.push(Node {tag}); self.next.push(0); } return self,Error.none; }
fn view(self: const Store&) -> View { assert(valid(self)); return View {self.owner_id,self.nodes.items,self.extra.items,self.effects.view(),self.quantifier_goals.items,self.quantifier_obligations.items}; }
fn node(self: const Store&,id: Id) -> Node { return view(self).node(id); }
fn children(self: const Store&,id: Id) -> const Id[:] { return view(self).children(id); }
fn goalEqual(left: const Goal[:],right: const Goal[:]) -> bool { if left.len!=right.len { return false; } for a,index in left { if a!=right[index] { return false; } } return true; }
fn put32(bytes: ByteBuffer&,value: u32) { for shift in 0..4 { bytes.push((value>>((shift*8) as u32)) as u8); } }
fn fingerprint(tag: Tag,a: u32,b: u32,row: u32,values: const Id[:],goals: const Goal[:]) -> u64 {
 var bytes=ByteBuffer {};  bytes.push(tagCode(tag)); put32(bytes,a); put32(bytes,b);
 if goals.len==0 { put32(bytes,row); }
 for word in values { put32(bytes,word); }
 for goal in goals {
  put32(bytes,goal.ty); bytes.push(blot_check_types::obligationKindCode(goal.kind) as u8); put32(bytes,goal.name); put32(bytes,goal.result); put32(bytes,goal.other); put32(bytes,goal.signature); bytes.push(blot_check_types::operatorCode(goal.operator) as u8); put32(bytes,goal.identity.unit); put32(bytes,goal.identity.decl); var explicit: u8=0; if goal.explicit { explicit=1; } bytes.push(explicit);
 }
 let __cleanup_result_1_0: u64 = blot_parse_symbols::wyhash(bytes.items); bytes.deinit(); return __cleanup_result_1_0;
 bytes.deinit(); }
fn intern(self: Store,tag: Tag,a: u32,b: u32,values: const Id[:]) -> Id,Error { return internWithEffects(self,tag,a,b,0,values); }
fn internWithEffects(self: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:]) -> Id,Error { return internFields(self,tag,a,b,row,values); }
fn internStateProvider(self: Store,read: Id,write: Id,state: Id) -> Id,Error { return internFields(self,Tag.state_provider,read,write,state,[]); }
fn internFields(self: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:]) -> Id,Error {
 if (tag==Tag.forall||tag==Tag.existential)&&values.len==0 {
  if b==0||b>128 { return 0,Error.type_mismatch; } var binders: Id[128];
  for ordinal in 0..b { let binder,err=intern(self,Tag.bound,ordinal as u32,0,[]); if err!=Error.none { return 0,err; } binders[ordinal]=binder; } return internFields(self,tag,a,b,row,binders[..b]);
 }
 var owned=WordBuffer {};  for value in values { owned.push(value); }
 if tag==Tag.record {
  if owned.len%2!=0 { let __cleanup_result_2_0: Id = 0; let __cleanup_result_2_1: Error = Error.type_mismatch; owned.deinit(); return __cleanup_result_2_0, __cleanup_result_2_1; }
  // Pair insertion sort keeps field identities adjacent to their evidence.
  var i=2; while i<owned.len { let name=owned.items[i]; let evidence=owned.items[i+1]; var j=i; while j>=2&&owned.items[j-2]>name { owned.items[j]=owned.items[j-2]; owned.items[j+1]=owned.items[j-1]; j-=2; } owned.items[j]=name; owned.items[j+1]=evidence; i+=2; }
  i=2; while i<owned.len { if owned.items[i]==owned.items[i-2] { let __cleanup_result_3_0: Id = 0; let __cleanup_result_3_1: Error = Error.type_mismatch; owned.deinit(); return __cleanup_result_3_0, __cleanup_result_3_1; } i+=2; }
 }
 let __cleanup_result_4_0, __cleanup_result_4_1 = internWithEffectsHashed(self,tag,a,b,row,owned.items,fingerprint(tag,a,b,row,owned.items,[])); owned.deinit(); return __cleanup_result_4_0, __cleanup_result_4_1;
 owned.deinit(); }
fn internHashed(self: Store,tag: Tag,a: u32,b: u32,values: const Id[:],hash: u64) -> Id,Error { return internWithEffectsHashed(self,tag,a,b,0,values,hash); }
fn internWithEffectsHashed(self: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:],hash: u64) -> Id,Error { return internGoalFields(self,tag,a,b,row,values,[],hash); }
fn internProjection(self: Store,identity: Identity,member: u32,arguments: const Id[:],scope: u32,goal: u32) -> Id,Error { var words=WordBuffer {};  words.append(arguments); words.push(member); words.push(scope); words.push(goal); let __cleanup_result_5_0, __cleanup_result_5_1 = intern(self,Tag.projection,identity.unit,identity.decl,words.items); words.deinit(); return __cleanup_result_5_0, __cleanup_result_5_1;  words.deinit(); }
fn internQuantifiedWithGoals(self: Store,tag: Tag,body: Id,binders: const Id[:],goals: const Goal[:]) -> Id,Error {
 if tag!=Tag.forall&&tag!=Tag.existential { return 0,Error.type_mismatch; }
 if goals.len==0 { return intern(self,tag,body,binders.len as u32,binders); }
 return internGoalFields(self,tag,body,binders.len as u32,0,binders,goals,fingerprint(tag,body,binders.len as u32,0,binders,goals));
}
fn internGoalFields(self: Store,tag: Tag,a: u32,b: u32,row: u32,values: const Id[:],goals: const Goal[:],hash: u64) -> Id,Error {
 if tag!=Tag.state_provider&&tag!=Tag.scoped&&tag!=Tag.usage&&tag!=Tag.bound&&(row>=self.effects.rows.len||(row!=0&&tag!=Tag.function&&tag!=Tag.provider)) { return 0,Error.type_mismatch; }
 if tag==Tag.absent { return 0,Error.unresolved_type; }
 if tag==Tag.usage {
  if a==0||a>=self.nodes.len||b>7||values.len!=0 { return 0,Error.type_mismatch; } let loan=b==2||b==3; if loan!=(row!=0) { return 0,Error.type_mismatch; }
  if loan&&(row>=self.nodes.len||node(self,row).tag!=Tag.bound||node(self,row).b!=2) { return 0,Error.type_mismatch; }
 } else if tag==Tag.erased_proof { if a!=0||b!=0||values.len!=0 { return 0,Error.type_mismatch; } }
 else if tag==Tag.unit||tag==Tag.boolean||tag==Tag.unsigned32||tag==Tag.floating32||tag==Tag.never { if a!=0||b!=0||values.len!=0 { return 0,Error.type_mismatch; } return tagCode(tag) as u32,Error.none; }
 else if tag==Tag.forall||tag==Tag.existential {
  if a==0||a>=self.nodes.len||b==0||b>128||row!=0||values.len!=b { return 0,Error.type_mismatch; }
  var remaining: i64=4096; let e=bodyWithGoalsValidated(view(self),a,values,goals,remaining,[]); if e!=Error.none { return 0,e; }
  if tag==Tag.existential { for binder in values { if node(self,binder).b!=0 { return 0,Error.type_mismatch; } } }
  for goal in goals {
   if goal.ty==0||blot_check_types::obligationKindCode(goal.kind)>blot_check_types::obligationKindCode(blot_check_types::ObligationKind.task_receive)||blot_check_types::operatorCode(goal.operator)>blot_check_types::operatorCode(blot_check_types::Operator.shift_right) { return 0,Error.type_mismatch; }
   let endpoints: Id[4]=[goal.ty,goal.other,goal.result,goal.signature]; for endpoint in endpoints { if endpoint!=0 { let error=bodyWithGoalsValidated(view(self),endpoint,values,goals,remaining,[]); if error!=Error.none { return 0,error; } } }
  }
 } else if tag==Tag.scoped { if a==0||a>=self.nodes.len||node(self,a).tag!=Tag.nominal||b==0||row==0||values.len!=0 { return 0,Error.type_mismatch; } }
 else if tag==Tag.bound { if a>=128||b>2||row>=128||values.len!=0 { return 0,Error.type_mismatch; } }
 else if tag==Tag.function { if values.len!=0||a==0||b==0||a>=self.nodes.len||b>=self.nodes.len { return 0,Error.type_mismatch; } }
 else if tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider { if values.len!=0||a==0||a>=self.nodes.len||b!=0 { return 0,Error.type_mismatch; } }
 else if tag==Tag.state_provider { if values.len!=0||a==0||b==0||row==0||a>=self.nodes.len||b>=self.nodes.len||row>=self.nodes.len { return 0,Error.type_mismatch; } }
 else if tag==Tag.product||tag==Tag.record { if a!=0||b!=0 { return 0,Error.type_mismatch; } }
 else if tag==Tag.projection { if a==0||b==0||values.len<3||values[values.len-3]==0||values[values.len-2]>=128||values[values.len-1]>=4096 { return 0,Error.type_mismatch; } }
 else if tag==Tag.nominal { if a==0 { return 0,Error.type_mismatch; } }
 else if tag==Tag.type_constructor { if a==0||b==0||values.len!=0 { return 0,Error.type_mismatch; } }
 if tag==Tag.provider&&node(self,a).tag!=Tag.nominal&&node(self,a).tag!=Tag.scoped { return 0,Error.type_mismatch; }
 if (tag==Tag.array||tag==Tag.list||tag==Tag.cursor||tag==Tag.resolver||tag==Tag.provider)&&node(self,a).tag==Tag.erased_proof { return 0,Error.type_mismatch; }
 if tag==Tag.state_provider&&((node(self,a).tag!=Tag.nominal&&node(self,a).tag!=Tag.scoped)||(node(self,b).tag!=Tag.nominal&&node(self,b).tag!=Tag.scoped)) { return 0,Error.type_mismatch; }
 for value,index in values {
  if tag==Tag.projection&&index>=values.len-3 { continue; }
  if tag==Tag.record&&index%2==0 { if value==0 { return 0,Error.type_mismatch; } }
  else if value==0||value>=self.nodes.len||node(self,value).tag==Tag.erased_proof { return 0,Error.type_mismatch; }
 }
 var candidate: Id=0; let bucket=self.buckets.get(hash); if bucket!=null { candidate=bucket; }
 while candidate!=0 {
  let n=node(self,candidate); var same=n.tag==tag;
  if same {
   if tag==Tag.product||tag==Tag.record { same=children(self,candidate)==values; }
   else if tag==Tag.nominal||tag==Tag.forall||tag==Tag.existential { same=n.a==a&&n.b==b&&children(self,candidate)==values; }
   else if tag==Tag.projection { same=n.a==a&&n.b==b&&self.extra.items[n.c+1..n.c+1+self.extra.items[n.c]+3]==values; }
   else { same=n.a==a&&n.b==b&&n.c==row; }
  }
  if same&&goalEqual(view(self).quantifierGoals(candidate),goals) { return candidate,Error.none; } candidate=self.next.items[candidate];
 }
 if self.nodes.len>=0xffffffff||values.len>=0xffffffff||self.extra.len>0xffffffff-values.len-1 { return 0,Error.evidence_limit; }
 if goals.len>0xffffffff-self.quantifier_obligations.len { return 0,Error.evidence_limit; }
 var n=Node {tag,a,b,row};
 if tag==Tag.product||tag==Tag.record { n.a=self.extra.len as u32; n.b=values.len as u32; if tag==Tag.record { n.b/=2; } self.extra.append(values); }
 else if tag==Tag.forall||tag==Tag.existential { n.c=self.extra.len as u32; self.extra.append(values); }
 else if tag==Tag.nominal||tag==Tag.projection { n.c=self.extra.len as u32; var count=values.len; if tag==Tag.projection { count-=3; } self.extra.push(count as u32); self.extra.append(values); }
 let id=self.nodes.len as Id;
 if goals.len!=0 { self.quantifier_goals.push(QuantifierGoals {id,blot_check_types::List {self.quantifier_obligations.len as u32,goals.len as u32}}); self.quantifier_obligations.append(goals); }
 var prior: Id=0; let previous=self.buckets.get(hash); if previous!=null { prior=previous; } self.nodes.push(n); self.next.push(prior); self.buckets.insert(hash,id); return id,Error.none;
}
fn containsAbstract(self: const Store&,id: Id) -> bool,Error { var remaining: i64=4096; return abstractDepth(self,id,0,remaining); }
fn abstractDepth(self: const Store&,id: Id,depth: i64,remaining: i64&) -> bool,Error {
 if depth>=128||remaining==0 { return false,Error.evidence_limit; } remaining--; let n=node(self,id);
 if n.tag==Tag.bound||n.tag==Tag.projection { return true,Error.none; } if n.tag==Tag.forall||n.tag==Tag.existential { return false,Error.none; }
 if n.tag==Tag.function||n.tag==Tag.state_provider {
  let a,e=abstractDepth(self,n.a,depth+1,remaining); if e!=Error.none||a { return a,e; } let b,error=abstractDepth(self,n.b,depth+1,remaining); if error!=Error.none||b { return b,error; }
  if n.tag==Tag.state_provider { return abstractDepth(self,n.c,depth+1,remaining); }
 } else if n.tag==Tag.scoped||n.tag==Tag.usage||n.tag==Tag.array||n.tag==Tag.list||n.tag==Tag.cursor||n.tag==Tag.resolver||n.tag==Tag.provider { return abstractDepth(self,n.a,depth+1,remaining); }
 else if n.tag==Tag.product||n.tag==Tag.record||n.tag==Tag.nominal { for child,index in children(self,id) { if n.tag==Tag.record&&index%2==0 { continue; } let found,err=abstractDepth(self,child,depth+1,remaining); if err!=Error.none||found { return found,err; } } }
 return false,Error.none;
}
struct ProjectionWork<S,R> { destination: Store,source: const S&,mappings: const Mapping[:],rows: const RowMapping[:],resolver: ProjectionResolver<R>&,failure: Error=Error.none }
fn accept<S,R>(work: ProjectionWork<S,R>&,id: Id,error: Error) -> Id { if work.failure==Error.none { work.failure=error; } return id; }
fn reject<S,R>(work: ProjectionWork<S,R>&,error: Error) -> Id { if work.failure==Error.none { work.failure=error; } return 0; }
fn projectDepth<S,R>(work: ProjectionWork<S,R>&,ty: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,parent_height: u16?) -> Id {
 if work.failure!=Error.none { return 0; } if depth>=1024||budget==0 { return reject(work,Error.evidence_limit); }
 if work.resolver.enabled {
  if depth>=256||work.resolver.remaining==0 { return reject(work,Error.evidence_limit); } work.resolver.remaining--;
  if ty>5&&memo!=null { let answer=memo.answers.get(ty); if answer!=null { let a=answer; if depth+a.height>256 { return reject(work,Error.evidence_limit); } budget--; if parent_height!=null&&parent_height!<a.height+1 { parent_height = a.height+1; } return a.value; } }
 }
 if retained&&ty>5&&memo!=null {
  let answer=memo.answers.get(ty); if answer!=null { let a=answer; if depth+a.height>1024||budget<a.visits { return reject(work,Error.evidence_limit); } budget-=a.visits; if parent_height!=null&&parent_height!<a.height+1 { parent_height = a.height+1; } return a.value; }
 }
 let before=budget; budget--; var height: u16=1; let result=projectNodeDepth(work,ty,depth,budget,retained,memo,height); if work.failure!=Error.none { return 0; }
 if retained||memo!=null {
  if parent_height!=null&&parent_height!<height+1 { parent_height = height+1; }
  if ty>5&&memo!=null { var visits: u32=1; if retained { visits=(before-budget) as u32; } memo.answers.insert(ty,blot_reuse_projection_cache::Answer {result,visits,height}); }
 }
 return result;
}
fn projectRowDepth<S,R>(work: ProjectionWork<S,R>&,row: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,parent_height: u16?) -> u32 {
 if work.failure!=Error.none { return 0; } if depth>=1024||budget==0 { return reject(work,Error.evidence_limit); } budget--;
 if work.resolver.enabled { if depth>=256||work.resolver.remaining==0 { return reject(work,Error.evidence_limit); } work.resolver.remaining--; }
 var height: u16=1; let result=projectRowBody(work,row,depth,budget,retained,memo,height);
 if memo!=null&&parent_height!=null&&parent_height!<height+1 { parent_height = height+1; } return result;
}
fn projectNodeDepth<S,R>(work: ProjectionWork<S,R>&,ty: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,height: u16&) -> Id {
 if work.failure!=Error.none { return 0; } let self=work.destination; let source=work.source;
 for mapping in mappingItems(work.mappings) { if mapping.variable==ty {
  if mapping.evidence==0||mapping.evidence>=self.nodes.len { return reject(work,Error.type_mismatch); } let leaf=node(self,mapping.evidence);
  if leaf.tag==Tag.erased_proof&&source.node(ty).tag!=blot_check_types::Tag.erased_proof { return reject(work,Error.type_mismatch); }
  if leaf.tag==Tag.bound {
   var scope=self.projection_owners.len;
   while scope!=0 { scope--; for binder in self.projection_owners.items[scope] { if binder==ty { let levels=self.projection_owners.len-1-scope; if levels>=128||leaf.c>127-levels { return reject(work,Error.evidence_limit); } let id,err=internWithEffects(self,Tag.bound,leaf.a,leaf.b,leaf.c+levels as u32,[]); return accept(work,id,err); } } }
  }
  return mapping.evidence;
 } }
 let n=source.node(ty); let tag=n.tag;
 if tag==blot_check_types::Tag.usage {
  var region: Id=0; if n.c!=0 { region=projectDepth(work,n.c,depth+1,budget,retained,memo,height); }
  let base=projectDepth(work,n.a,depth+1,budget,retained,memo,height); if work.failure!=Error.none { return 0; } let id,err=internWithEffects(self,Tag.usage,base,n.b,region,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.forall||tag==blot_check_types::Tag.existential {
  let source_binders=source.list(blot_check_types::List {n.b,n.c});
  if tag==blot_check_types::Tag.forall { var complete=true; for binder in source_binders { var found=false; for mapping in mappingItems(work.mappings) { if mapping.variable==binder { found=true; break; } } complete=complete&&found; } if complete&&source.quantifierGoals(ty).len==0 { return projectDepth(work,n.a,depth+1,budget,retained,memo,height); } }
  if depth>=128||n.c==0||n.c>128 { return reject(work,Error.evidence_limit); }
  var owned=MappingBuffer {}; 
  for binder,ordinal in source_binders { let leaf=source.node(binder); if leaf.tag!=blot_check_types::Tag.bound||leaf.a!=ordinal||leaf.b>2||leaf.c!=0 { let __cleanup_result_6_0: Id = reject(work,Error.unresolved_type); owned.deinit(); return __cleanup_result_6_0; } let id,error=intern(self,Tag.bound,ordinal as u32,leaf.b,[]); if error!=Error.none { let __cleanup_result_7_0: Id = reject(work,error); owned.deinit(); return __cleanup_result_7_0; } owned.push(Mapping {binder,id}); }
  owned.append(work.mappings); self.projection_owners.push(source_binders); self.projection_quantifiers.push(ty);
  let saved_mappings=work.mappings; work.mappings=owned.items; var body_budget=budget; if body_budget>4096 { body_budget=4096; } let available=body_budget;
  
  let body=projectDepth(work,n.a,depth+1,body_budget,false,null,height); var result_tag=Tag.existential; if tag==blot_check_types::Tag.forall { result_tag=Tag.forall; }
  var binders: Id[128]; for mapping,index in owned.items[..n.c] { binders[index]=mapping.evidence; } var goals=GoalBuffer {}; 
  for goal in source.quantifierGoals(ty) {
   if body_budget==0 { let __cleanup_result_87_0: Id = reject(work,Error.evidence_limit); { work.mappings=saved_mappings; self.projection_owners.resize(self.projection_owners.len-1); self.projection_quantifiers.resize(self.projection_quantifiers.len-1); budget-=available-body_budget; } let __cleanup_result_8_0: Id = __cleanup_result_87_0; goals.deinit(); owned.deinit(); return __cleanup_result_8_0; } body_budget--; var value=Goal {ty:0,kind:goal.kind,name:goal.name,operator:goal.operator,identity:goal.identity,explicit:goal.explicit};
   if goal.ty!=0 { value.ty=projectDepth(work,goal.ty,depth+1,body_budget,false,null,height); } if goal.other!=0 { value.other=projectDepth(work,goal.other,depth+1,body_budget,false,null,height); } if goal.result!=0 { value.result=projectDepth(work,goal.result,depth+1,body_budget,false,null,height); } if goal.signature!=0 { value.signature=projectDepth(work,goal.signature,depth+1,body_budget,false,null,height); } goals.push(value);
  }
  if work.failure!=Error.none { let __cleanup_result_88_0: Id = 0; { work.mappings=saved_mappings; self.projection_owners.resize(self.projection_owners.len-1); self.projection_quantifiers.resize(self.projection_quantifiers.len-1); budget-=available-body_budget; } let __cleanup_result_9_0: Id = __cleanup_result_88_0; goals.deinit(); owned.deinit(); return __cleanup_result_9_0; } let id,err=internQuantifiedWithGoals(self,result_tag,body,binders[..n.c],goals.items); let __cleanup_result_89_0: Id = accept(work,id,err); { work.mappings=saved_mappings; self.projection_owners.resize(self.projection_owners.len-1); self.projection_quantifiers.resize(self.projection_quantifiers.len-1); budget-=available-body_budget; } let __cleanup_result_10_0: Id = __cleanup_result_89_0; goals.deinit(); owned.deinit(); return __cleanup_result_10_0;
  { work.mappings=saved_mappings; self.projection_owners.resize(self.projection_owners.len-1); self.projection_quantifiers.resize(self.projection_quantifiers.len-1); budget-=available-body_budget; }  goals.deinit(); owned.deinit(); }
 if tag==blot_check_types::Tag.scoped {
  let descriptor=projectDepth(work,n.a,depth+1,budget,retained,memo,height); var instance=blot_check_types::selectionAtom(source,Identity {n.b,n.c});
  if instance.unit==0 { let owner_id=projectDepth(work,n.c,depth+1,budget,retained,memo,height); if work.failure!=Error.none { return 0; } let owner=node(self,owner_id); if owner.tag!=Tag.scoped { return reject(work,Error.unresolved_type); } instance=Identity {owner.b,owner.c}; }
  if instance.unit==0||instance.decl==0 { return reject(work,Error.unresolved_type); } let id,err=internWithEffects(self,Tag.scoped,descriptor,instance.unit,instance.decl,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.instance_version||tag==blot_check_types::Tag.bound||tag==blot_check_types::Tag.rigid||tag==blot_check_types::Tag.instance_selection||tag==blot_check_types::Tag.variable||tag==blot_check_types::Tag.absent { return reject(work,Error.unresolved_type); }
 if tag==blot_check_types::Tag.erased_proof { let id,err=intern(self,Tag.erased_proof,0,0,[]); return accept(work,id,err); }
 if tag==blot_check_types::Tag.unit { return 1; } if tag==blot_check_types::Tag.boolean { return 2; } if tag==blot_check_types::Tag.unsigned32 { return 3; } if tag==blot_check_types::Tag.floating32 { return 4; } if tag==blot_check_types::Tag.never { return 5; }
 if tag==blot_check_types::Tag.projection {
  let input=source.nominalArguments(n); var arguments=WordBuffer {};  for root in input { arguments.push(projectDepth(work,root,depth+1,budget,retained,memo,height)); }
  var owner_index=self.projection_quantifiers.len;
  while owner_index!=0 {
   owner_index--; let owner=self.projection_quantifiers.items[owner_index];
   for goal,ordinal in source.quantifierGoals(owner) {
    if budget==0 { let __cleanup_result_11_0: Id = reject(work,Error.evidence_limit); arguments.deinit(); return __cleanup_result_11_0; } budget--;
    if goal.kind!=blot_check_types::ObligationKind.contract||goal.identity.unit!=n.a||goal.identity.decl!=n.b { continue; } let tuple=source.node(goal.ty); if tuple.tag!=blot_check_types::Tag.product||tuple.b!=input.len { continue; }
    var matches=true; for expected,index in source.list(blot_check_types::List {tuple.a,tuple.b}) { let projected=projectDepth(work,expected,depth+1,budget,retained,memo,height); if projected!=arguments.items[index] { matches=false; } }
    if matches&&work.failure==Error.none { let id,err=internProjection(self,Identity {n.a,n.b},source.projectionMember(n),arguments.items,(self.projection_quantifiers.len-1-owner_index) as u32,ordinal as u32); let __cleanup_result_12_0: Id = accept(work,id,err); arguments.deinit(); return __cleanup_result_12_0; }
   }
  }
  if work.failure!=Error.none { let __cleanup_result_13_0: Id = 0; arguments.deinit(); return __cleanup_result_13_0; } if !work.resolver.enabled { let __cleanup_result_14_0: Id = reject(work,Error.unresolved_type); arguments.deinit(); return __cleanup_result_14_0; }
  let id,err=work.resolver.context.resolve(Identity {n.a,n.b},source.projectionMember(n),arguments.items); let __cleanup_result_15_0: Id = accept(work,id,err); arguments.deinit(); return __cleanup_result_15_0;
  arguments.deinit(); }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider {
  let child=projectDepth(work,n.a,depth+1,budget,retained,memo,height); var result_tag=Tag.array;
  if tag==blot_check_types::Tag.list { result_tag=Tag.list; } else if tag==blot_check_types::Tag.cursor { result_tag=Tag.cursor; } else if tag==blot_check_types::Tag.resolver { result_tag=Tag.resolver; } else if tag==blot_check_types::Tag.provider { result_tag=Tag.provider; }
  var row: u32=0; if result_tag==Tag.provider { row=projectRowDepth(work,n.c,depth+1,budget,retained,memo,height); } if work.failure!=Error.none { return 0; }
  let id,err=internWithEffects(self,result_tag,child,0,row,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.state_provider||tag==blot_check_types::Tag.function {
  let a=projectDepth(work,n.a,depth+1,budget,retained,memo,height); let b=projectDepth(work,n.b,depth+1,budget,retained,memo,height); var c: u32=0;
  if tag==blot_check_types::Tag.function { c=projectRowDepth(work,n.c,depth+1,budget,retained,memo,height); } else { c=projectDepth(work,n.c,depth+1,budget,retained,memo,height); }
  if work.failure!=Error.none { return 0; } var result_tag=Tag.function; if tag==blot_check_types::Tag.state_provider { result_tag=Tag.state_provider; } let id,err=internWithEffects(self,result_tag,a,b,c,[]); return accept(work,id,err);
 }
 if tag==blot_check_types::Tag.type_constructor { let id,err=intern(self,Tag.type_constructor,n.a,n.b,[]); return accept(work,id,err); }
 var values=WordBuffer {};  var result_tag=Tag.product; var a: u32=0; var b: u32=0;
 if tag==blot_check_types::Tag.record { result_tag=Tag.record; for index in 0..n.b { let field=source.recordField(n,index); values.push(field.name); values.push(projectDepth(work,field.ty,depth+1,budget,retained,memo,height)); } }
 else if tag==blot_check_types::Tag.nominal { result_tag=Tag.nominal; a=n.a; b=n.b; for child in source.nominalArguments(n) { values.push(projectDepth(work,child,depth+1,budget,retained,memo,height)); } }
 else { for child in source.list(blot_check_types::List {n.a,n.b}) { values.push(projectDepth(work,child,depth+1,budget,retained,memo,height)); } }
 if work.failure!=Error.none { let __cleanup_result_16_0: Id = 0; values.deinit(); return __cleanup_result_16_0; } let id,err=intern(self,result_tag,a,b,values.items); let __cleanup_result_17_0: Id = accept(work,id,err); values.deinit(); return __cleanup_result_17_0;
 values.deinit(); }
fn projectRowBody<S,R>(work: ProjectionWork<S,R>&,row: u32,depth: i64,budget: i64&,retained: bool,memo: blot_reuse_projection_cache::Cache?,height: u16&) -> u32 {
 let self=work.destination; let source=work.source; var suffix: u32=0; var formal: Id=0;
 match source.row(row).tail {
  closed=>{},
  formal leaf=>{
   let key,err=blot_check_types::formalRowKey(leaf.value); if err!=Error.none { return reject(work,Error.unresolved_type); } var replaced=false;
   for mapping in mappingItems(work.rows) { if mapping.variable==key { if mapping.evidence>=self.effects.rows.len { return reject(work,Error.type_mismatch); } suffix=mapping.evidence; replaced=true; break; } }
   if !replaced { formal=projectDepth(work,leaf.value,depth+1,budget,retained,memo,height); if work.failure!=Error.none { return 0; } let projected=node(self,formal); if projected.tag!=Tag.bound||projected.b!=1 { return reject(work,Error.type_mismatch); } }
  },
  parameter=>{ return reject(work,Error.unresolved_type); },
  variable v=>{ var found=false; for mapping in mappingItems(work.rows) { if mapping.variable==v.value { if mapping.evidence>=self.effects.rows.len { return reject(work,Error.type_mismatch); } suffix=mapping.evidence; found=true; break; } } if !found { return reject(work,Error.unresolved_type); } },
 }
 var labels=WordBuffer {};  var arguments=WordBuffer {}; 
 for label in source.rowLabels(row) {
  if work.resolver.enabled { if work.resolver.remaining==0 { let __cleanup_result_18_0: u32 = reject(work,Error.evidence_limit); arguments.deinit(); labels.deinit(); return __cleanup_result_18_0; } work.resolver.remaining--; }
  if retained&&memo!=null { let answer=memo.labels.get(label); if answer!=null { let a=answer; if depth+a.height>1024||budget<a.visits { let __cleanup_result_19_0: u32 = reject(work,Error.evidence_limit); arguments.deinit(); labels.deinit(); return __cleanup_result_19_0; } budget-=a.visits; if height<a.height { height=a.height; } labels.push(a.value); continue; } }
  let operation=source.operation(label); let instance=blot_check_types::selectionAtom(source,operation.instance); if instance.unit==0&&instance.decl!=0 { let __cleanup_result_20_0: u32 = reject(work,Error.unresolved_type); arguments.deinit(); labels.deinit(); return __cleanup_result_20_0; }
  arguments.resize(0); let before=budget; var label_height: u16=0;
  for argument in source.operationArguments(label) { if retained { arguments.push(projectDepth(work,argument,depth+1,budget,retained,memo,label_height)); } else { arguments.push(projectDepth(work,argument,depth+1,budget,retained,memo,height)); } }
  if work.failure!=Error.none { let __cleanup_result_21_0: u32 = 0; arguments.deinit(); labels.deinit(); return __cleanup_result_21_0; } let projected,err=self.effects.internOperationInstance(operation.identity,arguments.items,instance); if err!=Error.none { let __cleanup_result_22_0: u32 = reject(work,err); arguments.deinit(); labels.deinit(); return __cleanup_result_22_0; }
  if retained&&memo!=null { if height<label_height { height=label_height; } memo.labels.insert(label,blot_reuse_projection_cache::Answer {projected,(before-budget) as u32,label_height}); } labels.push(projected);
 }
 labels.append(self.effects.view().rowLabels(suffix)); if suffix!=0 { formal=self.effects.rows.items[suffix].formal; } let result,err=self.effects.internRowWithFormal(labels.items,formal); let __cleanup_result_23_0: u32 = accept(work,result,err); arguments.deinit(); labels.deinit(); return __cleanup_result_23_0;
 arguments.deinit(); labels.deinit(); }
fn project<S>(self: Store,source: const S&,ty: u32,mappings: const Mapping[:]) -> Id,Error { return projectWithRows(self,source,ty,mappings,[]); }
fn projectWithRows<S>(self: Store,source: const S&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:]) -> Id,Error { var budget: i64=1000000; return projectWithBudget(self,source,ty,mappings,rows,budget); }
fn projectWithBudget<S>(self: Store,source: const S&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:],budget: i64&) -> Id,Error {
 var no=NoResolver {}; var remaining: i64=0; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=ProjectionWork<S,NoResolver> {self,source,mappings,rows,resolver}; let id=projectDepth(work,ty,0,budget,false,null,null); return id,work.failure;
}
fn projectSelected<S,R>(self: Store,source: const S&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:],resolver: ProjectionResolver<R>&) -> Id,Error {
 var budget: i64=1000000; let initialized,cache_error=blot_reuse_projection_cache::initPooled(); if cache_error!=Error.none { return 0,cache_error; } var memo=initialized;  var work=ProjectionWork<S,R> {self,source,mappings,rows,resolver}; let id=projectDepth(work,ty,0,budget,false,memo,null); let __cleanup_result_1_0: Id = id; let __cleanup_result_1_1: Error = work.failure; memo.deinit(); return __cleanup_result_1_0, __cleanup_result_1_1;
 memo.deinit(); }
fn projectEffects<S>(self: Store,source: const S&,row: u32,mappings: const Mapping[:],rows: const RowMapping[:]) -> u32,Error {
 var no=NoResolver {}; var remaining: i64=0; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=ProjectionWork<S,NoResolver> {self,source,mappings,rows,resolver}; var budget: i64=1000000; let id=projectRowDepth(work,row,0,budget,false,null,null); return id,work.failure;
}
fn projectOwned(self: Store,source: const blot_check_types::Store&,ty: u32,memo: blot_reuse_projection_cache::Cache&) -> Id,Error {
 if !memo.activate(source.owner_id,self.owner_id,source.closed_generation,source.effects.physical_epoch) { return project(self,source,ty,[]); }
 var no=NoResolver {}; var remaining: i64=0; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=ProjectionWork<blot_check_types::Store,NoResolver> {self,source,[],[],resolver}; var budget: i64=1000000; let id=projectDepth(work,ty,0,budget,true,memo,null); return id,work.failure;
}
fn projectAssociatedOwned(self: Store,source: const blot_check_types::Store&,ty: u32,memo: blot_reuse_projection_cache::Cache&,remaining: i64&) -> Id,Error {
 var no=NoResolver {}; var resolver=ProjectionResolver<NoResolver> {no,remaining,true}; if !memo.activate(source.owner_id,self.owner_id,source.closed_generation,source.effects.physical_epoch) { return projectSelected(self,source,ty,[],[],resolver); }
 var work=ProjectionWork<blot_check_types::Store,NoResolver> {self,source,[],[],resolver}; var budget: i64=1000000; let id=projectDepth(work,ty,0,budget,false,memo,null); return id,work.failure;
}
struct MatchWork<S,R,M,B> { destination: Store,source: const S&,mappings: M,rows: B,has_rows: bool,resolver: ProjectionResolver<R>&,memo: MatchMemo,use_memo: bool,failure: Error=Error.none }
fn matchFail<S,R,M,B>(work: MatchWork<S,R,M,B>&,error: Error) -> bool { if work.failure==Error.none { work.failure=error; } return false; }
fn matchDepth<S,R,M,B>(work: MatchWork<S,R,M,B>&,pattern: u32,actual: Id,depth: i64,budget: i64&) -> bool {
 if work.failure!=Error.none { return false; } if depth>=1024||(work.use_memo&&depth>=256)||budget==0 { return matchFail(work,Error.evidence_limit); } budget--;
 let self=work.destination; let source=work.source; if actual==0||actual>=self.nodes.len { return matchFail(work,Error.unresolved_type); }
 let pair=(pattern as u64)<<32|actual; if work.use_memo&&work.memo.contains(pair) { return true; } let n=source.node(pattern); let tag=n.tag;
 if tag==blot_check_types::Tag.projection {
  if !work.resolver.enabled { return false; } let normalized,err=projectSelected(self,source,pattern,mappingItems(work.mappings),mappingItems(work.rows),work.resolver);
  if err==Error.unresolved_type { return false; } if err!=Error.none { return matchFail(work,err); } if normalized!=actual { return false; } if work.use_memo { work.memo.insert(pair,true); } return true;
 }
 let concrete=node(self,actual);
 if tag==blot_check_types::Tag.existential||(tag==blot_check_types::Tag.forall&&concrete.tag==Tag.forall) {
  var wanted=Tag.existential; if tag==blot_check_types::Tag.forall { wanted=Tag.forall; } if concrete.tag!=wanted||n.c!=concrete.b { return false; }
  let expected,err=projectWithRows(self,source,pattern,mappingItems(work.mappings),mappingItems(work.rows)); if err==Error.unresolved_type { return false; } if err!=Error.none { return matchFail(work,err); } return expected==actual;
 }
 if tag==blot_check_types::Tag.never||concrete.tag==Tag.never { return true; }
 if tag==blot_check_types::Tag.forall { return matchDepth(work,n.a,actual,depth+1,budget); }
 if tag==blot_check_types::Tag.variable||(tag==blot_check_types::Tag.bound&&n.b==0) {
  if concrete.tag==Tag.erased_proof { return false; } for mapping in mappingItems(work.mappings) { if mapping.variable==pattern { return mapping.evidence==actual; } } work.mappings.push(Mapping {pattern,actual}); if mappingFailure(work.mappings)!=Error.none { return matchFail(work,mappingFailure(work.mappings)); } return true;
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
    var known=false; for mapping in mappingItems(work.mappings) { if mapping.variable==owner { let prior=node(self,mapping.evidence); if prior.tag!=Tag.scoped||prior.b!=concrete.b||prior.c!=concrete.c { return false; } known=true; break; } }
    if !known { work.mappings.push(Mapping {owner,actual}); if mappingFailure(work.mappings)!=Error.none { return matchFail(work,mappingFailure(work.mappings)); } }
   } else { let atom=blot_check_types::selectionAtom(source,Identity {0,owner}); if atom.unit!=concrete.b||atom.decl!=concrete.c { return false; } }
  }
 } else if tag==blot_check_types::Tag.usage||tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider { if !matchDepth(work,n.a,concrete.a,depth+1,budget) { return false; } }
 else if tag==blot_check_types::Tag.state_provider { if !matchDepth(work,n.a,concrete.a,depth+1,budget)||!matchDepth(work,n.b,concrete.b,depth+1,budget)||!matchDepth(work,n.c,concrete.c,depth+1,budget) { return false; } }
 else if tag==blot_check_types::Tag.function { if !matchDepth(work,n.a,concrete.a,depth+1,budget)||!matchRowDepth(work,n.c,concrete.c,depth+1,budget)||!matchDepth(work,n.b,concrete.b,depth+1,budget) { return false; } }
 else if tag==blot_check_types::Tag.product||tag==blot_check_types::Tag.nominal {
  var expected=source.list(blot_check_types::List {n.a,n.b}); if tag==blot_check_types::Tag.nominal { expected=source.nominalArguments(n); }
  var actuals=WordBuffer {};  actuals.append(children(self,actual)); if expected.len!=actuals.len { let __cleanup_result_24_0: bool = false; actuals.deinit(); return __cleanup_result_24_0; }
  for child,index in expected { if !matchDepth(work,child,actuals.items[index],depth+1,budget) { let __cleanup_result_25_0: bool = false; actuals.deinit(); return __cleanup_result_25_0; } }
  actuals.deinit(); } else if tag==blot_check_types::Tag.record {
  var fields=WordBuffer {};  fields.append(children(self,actual)); if fields.len!=(n.b as i64)*2 { let __cleanup_result_26_0: bool = false; fields.deinit(); return __cleanup_result_26_0; }
  for index in 0..n.b { let field=source.recordField(n,index); var found=false; var i=0; while i<fields.len { if fields.items[i]==field.name { if !matchDepth(work,field.ty,fields.items[i+1],depth+1,budget) { let __cleanup_result_27_0: bool = false; fields.deinit(); return __cleanup_result_27_0; } found=true; break; } i+=2; } if !found { let __cleanup_result_28_0: bool = false; fields.deinit(); return __cleanup_result_28_0; } }
  fields.deinit(); }
 if work.use_memo { work.memo.insert(pair,true); } return true;
}
fn matchRowDepth<S,R,M,B>(work: MatchWork<S,R,M,B>&,pattern: u32,actual: u32,depth: i64,budget: i64&) -> bool {
 if work.failure!=Error.none { return false; } let self=work.destination; let source=work.source; let tail=source.row(pattern).tail; var closed=false;
 match tail {
  parameter=>{ return matchFail(work,Error.unresolved_type); },
  variable=>{ if !work.has_rows { return matchFail(work,Error.unresolved_type); } },
  formal=>{
   var projection=ProjectionWork<S,R> {self,source,mappingItems(work.mappings),mappingItems(work.rows),work.resolver}; let expected=projectRowDepth(projection,pattern,depth+1,budget,false,null,null); if projection.failure!=Error.none { return matchFail(work,projection.failure); } return actual==expected;
  },
  closed=>{ closed=true; },
 }
 let actual_formal=self.effects.rows.items[actual].formal; if closed&&actual_formal!=0 { return false; }
 let expected=source.rowLabels(pattern); var actuals=WordBuffer {};  actuals.append(self.effects.view().rowLabels(actual));
 if expected.len>actuals.len||(closed&&expected.len!=actuals.len) { let __cleanup_result_29_0: bool = false; actuals.deinit(); return __cleanup_result_29_0; } var used=BoolBuffer {};  used.resize(actuals.len,false);
 let __cleanup_result_30_0: bool = matchOperations(work,expected,actuals.items,used.items,tail,actual_formal,0,depth,budget); used.deinit(); actuals.deinit(); return __cleanup_result_30_0;
 used.deinit(); actuals.deinit(); }
fn matchOperations<S,R,M,B>(work: MatchWork<S,R,M,B>&,expected: const u32[:],actuals: const u32[:],used: bool[:],tail: blot_check_effects::Tail,actual_formal: Id,index: i64,depth: i64,budget: i64&) -> bool {
 if work.failure!=Error.none { return false; } if depth>=1024||(work.use_memo&&depth>=256)||budget==0 { return matchFail(work,Error.evidence_limit); } budget--;
 let self=work.destination; let source=work.source;
 if index==expected.len {
  match tail {
   closed=>{ return true; },
   variable variable=>{
    var remaining=WordBuffer {};  for label,i in actuals { if !used[i] { remaining.push(label); } }
    let suffix,err=self.effects.internRowWithFormal(remaining.items,actual_formal); if err!=Error.none { let __cleanup_result_31_0: bool = matchFail(work,err); remaining.deinit(); return __cleanup_result_31_0; }
    for mapping in mappingItems(work.rows) { if mapping.variable==variable.value { let __cleanup_result_32_0: bool = mapping.evidence==suffix; remaining.deinit(); return __cleanup_result_32_0; } } work.rows.push(RowMapping {variable.value,suffix}); if mappingFailure(work.rows)!=Error.none { return matchFail(work,mappingFailure(work.rows)); } let __cleanup_result_33_0: bool = true; remaining.deinit(); return __cleanup_result_33_0;
    remaining.deinit(); },
   _=>{ return matchFail(work,Error.unresolved_type); },
  }
 }
 let operation=source.operation(expected[index]); let arguments=source.operationArguments(expected[index]);
 for label,i in actuals {
  if work.use_memo { if budget==0 { return matchFail(work,Error.evidence_limit); } budget--; } if used[i] { continue; }
  let concrete=self.effects.view().operation(label); let atom=blot_check_types::selectionAtom(source,operation.instance);
  if atom!=concrete.instance||operation.identity.unit!=concrete.identity.unit||operation.identity.decl!=concrete.identity.decl { continue; }
  var actual_arguments=WordBuffer {};  actual_arguments.append(self.effects.view().operationArguments(label)); if arguments.len!=actual_arguments.len { actual_arguments.deinit(); continue; }
  let frontier=work.mappings.len; let row_frontier=work.rows.len; var same=true;
  for argument,j in arguments { if !matchDepth(work,argument,actual_arguments.items[j],depth+1,budget) { same=false; break; } }
  if work.failure!=Error.none { let __cleanup_result_35_0: bool = false; actual_arguments.deinit(); return __cleanup_result_35_0; }
  if same { used[i]=true; if matchOperations(work,expected,actuals,used,tail,actual_formal,index+1,depth+1,budget) { let __cleanup_result_36_0: bool = true; actual_arguments.deinit(); return __cleanup_result_36_0; } used[i]=false; }
  if work.failure!=Error.none { let __cleanup_result_37_0: bool = false; actual_arguments.deinit(); return __cleanup_result_37_0; } if work.use_memo { work.memo.clear(); } work.mappings.resize(frontier); work.rows.resize(row_frontier);
  actual_arguments.deinit(); }
 return false;
}
fn matchWithRowsBudgetInner<S,M,B>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,budget: i64&) -> bool,Error {
 var no=NoResolver {}; var remaining: i64=0; var resolver=ProjectionResolver<NoResolver> {no,remaining,false};  var work=MatchWork<S,NoResolver,M,B> {self,source,mappings,rows,true,resolver,MatchMemo {},true};  let frontier=mappings.len; let row_frontier=rows.len;
 let accepted=matchDepth(work,pattern,actual,0,budget); if !accepted||work.failure!=Error.none { mappings.resize(frontier); rows.resize(row_frontier); } let __cleanup_result_38_0: bool = accepted; let __cleanup_result_38_1: Error = work.failure; work.memo.deinit(); return __cleanup_result_38_0, __cleanup_result_38_1;
 work.memo.deinit(); }
fn matchWithRowsInner<S,M,B>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B) -> bool,Error {
 var no=NoResolver {}; var remaining: i64=0; var resolver=ProjectionResolver<NoResolver> {no,remaining,false};  var work=MatchWork<S,NoResolver,M,B> {self,source,mappings,rows,true,resolver,MatchMemo {},false};  var budget: i64=1000000; let frontier=mappings.len; let row_frontier=rows.len;
 let accepted=matchDepth(work,pattern,actual,0,budget); if !accepted||work.failure!=Error.none { mappings.resize(frontier); rows.resize(row_frontier); } let __cleanup_result_39_0: bool = accepted; let __cleanup_result_39_1: Error = work.failure; work.memo.deinit(); return __cleanup_result_39_0, __cleanup_result_39_1;
 work.memo.deinit(); }
fn match_<S>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&) -> bool,Error {
 var rows=PooledRows {};  let activated=activate(rows); if activated!=Error.none { let __cleanup_result_40_0: bool = false; let __cleanup_result_40_1: Error = activated; rows.deinit(); return __cleanup_result_40_0, __cleanup_result_40_1; } var no=NoResolver {}; var remaining: i64=0; var resolver=ProjectionResolver<NoResolver> {no,remaining,false}; var work=MatchWork<S,NoResolver,Mapping[>..<]&,PooledRows> {self,source,mappings,rows,false,resolver,MatchMemo {},false};  var budget: i64=1000000; let frontier=mappings.len;
 let accepted=matchDepth(work,pattern,actual,0,budget); if !accepted||work.failure!=Error.none { mappings.resize(frontier); } let __cleanup_result_41_0: bool = accepted; let __cleanup_result_41_1: Error = work.failure; work.memo.deinit(); rows.deinit(); return __cleanup_result_41_0, __cleanup_result_41_1;
 work.memo.deinit(); rows.deinit(); }
fn matchSelectedInner<S,R,M,B>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> bool,Error {
  var work=MatchWork<S,R,M,B> {self,source,mappings,rows,true,resolver,MatchMemo {},true};  let frontier=mappings.len; let row_frontier=rows.len; let accepted=matchDepth(work,pattern,actual,0,resolver.remaining); if !accepted||work.failure!=Error.none { mappings.resize(frontier); rows.resize(row_frontier); } let __cleanup_result_42_0: bool = accepted; let __cleanup_result_42_1: Error = work.failure; work.memo.deinit(); return __cleanup_result_42_0, __cleanup_result_42_1;
 work.memo.deinit(); }
fn matchSignatureInner<S,R,M,B>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&,infer_rows: bool) -> bool,Error {
  var work=MatchWork<S,R,M,B> {self,source,mappings,rows,true,resolver,MatchMemo {},true};  let frontier=mappings.len; let row_frontier=rows.len; var accepted=false;
 
 var expected=pattern; var supplied=actual; var depth=0;
 while source.node(expected).tag==blot_check_types::Tag.forall { if depth>=128 { let __cleanup_result_90_0: bool = false; let __cleanup_result_90_1: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_43_0: bool = __cleanup_result_90_0; let __cleanup_result_43_1: Error = __cleanup_result_90_1; work.memo.deinit(); return __cleanup_result_43_0, __cleanup_result_43_1; } depth++; expected=source.node(expected).a; }
 while source.node(expected).tag==blot_check_types::Tag.function {
  if depth>=256||resolver.remaining==0 { let __cleanup_result_91_0: bool = false; let __cleanup_result_91_1: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_44_0: bool = __cleanup_result_91_0; let __cleanup_result_44_1: Error = __cleanup_result_91_1; work.memo.deinit(); return __cleanup_result_44_0, __cleanup_result_44_1; } resolver.remaining--; let arrow=source.node(expected); let concrete=node(self,supplied); if concrete.tag!=Tag.function { let __cleanup_result_92_0: bool = false; let __cleanup_result_92_1: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_45_0: bool = __cleanup_result_92_0; let __cleanup_result_45_1: Error = __cleanup_result_92_1; work.memo.deinit(); return __cleanup_result_45_0, __cleanup_result_45_1; }
  if !matchDepth(work,arrow.a,concrete.a,depth+1,resolver.remaining) { let __cleanup_result_93_0: bool = false; let __cleanup_result_93_1: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_46_0: bool = __cleanup_result_93_0; let __cleanup_result_46_1: Error = __cleanup_result_93_1; work.memo.deinit(); return __cleanup_result_46_0, __cleanup_result_46_1; }
  var projection=ProjectionWork<S,R> {self,source,mappingItems(mappings),mappingItems(rows),resolver}; var required_row=projectRowDepth(projection,arrow.c,depth+1,resolver.remaining,false,null,null);
  if projection.failure==Error.unresolved_type {
   if !infer_rows { let __cleanup_result_94_0: bool = false; let __cleanup_result_94_1: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_47_0: bool = __cleanup_result_94_0; let __cleanup_result_47_1: Error = __cleanup_result_94_1; work.memo.deinit(); return __cleanup_result_47_0, __cleanup_result_47_1; } if !matchRowDepth(work,arrow.c,concrete.c,depth+1,resolver.remaining) { let __cleanup_result_95_0: bool = false; let __cleanup_result_95_1: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_48_0: bool = __cleanup_result_95_0; let __cleanup_result_48_1: Error = __cleanup_result_95_1; work.memo.deinit(); return __cleanup_result_48_0, __cleanup_result_48_1; }
   projection.failure=Error.none; projection.mappings=mappingItems(mappings); projection.rows=mappingItems(rows); required_row=projectRowDepth(projection,arrow.c,depth+1,resolver.remaining,false,null,null);
  }
  if projection.failure!=Error.none { let __cleanup_result_96_0: bool = false; let __cleanup_result_96_1: Error = projection.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_49_0: bool = __cleanup_result_96_0; let __cleanup_result_49_1: Error = __cleanup_result_96_1; work.memo.deinit(); return __cleanup_result_49_0, __cleanup_result_49_1; }
  var required=WordBuffer {};  required.append(self.effects.view().rowLabels(required_row));
  for label in required.items { if resolver.remaining==0 { let __cleanup_result_97_0: bool = false; let __cleanup_result_97_1: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_50_0: bool = __cleanup_result_97_0; let __cleanup_result_50_1: Error = __cleanup_result_97_1; required.deinit(); work.memo.deinit(); return __cleanup_result_50_0, __cleanup_result_50_1; } resolver.remaining--; var found=false; for actual in self.effects.view().rowLabels(concrete.c) { if actual==label { found=true; break; } } if !found { let __cleanup_result_98_0: bool = false; let __cleanup_result_98_1: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_51_0: bool = __cleanup_result_98_0; let __cleanup_result_51_1: Error = __cleanup_result_98_1; required.deinit(); work.memo.deinit(); return __cleanup_result_51_0, __cleanup_result_51_1; } }
  expected=arrow.b; supplied=concrete.b; depth++;
  required.deinit(); }
 accepted=matchDepth(work,expected,supplied,depth+1,resolver.remaining); let __cleanup_result_99_0: bool = accepted; let __cleanup_result_99_1: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_52_0: bool = __cleanup_result_99_0; let __cleanup_result_52_1: Error = __cleanup_result_99_1; work.memo.deinit(); return __cleanup_result_52_0, __cleanup_result_52_1;
 { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } }  work.memo.deinit(); }
fn matchTemplateInner<S,R,M,B>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> bool,Error { return matchSignatureInner<S,R,M,B>(self,source,pattern,actual,mappings,rows,resolver,false); }
fn matchLegacySignatureInner<S,R,M,B>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> bool,Error { return matchSignatureInner<S,R,M,B>(self,source,pattern,actual,mappings,rows,resolver,true); }
fn matchPrerequisiteInner<S,R,M,B>(self: Store,source: const S&,pattern: u32,operands: Id[4],arity: i64,mappings: M,rows: B,resolver: ProjectionResolver<R>&) -> Id,bool,Error {
  var work=MatchWork<S,R,M,B> {self,source,mappings,rows,true,resolver,MatchMemo {},true};  var labels=WordBuffer {};  let frontier=mappings.len; let row_frontier=rows.len; var accepted=false;
 
 var required=pattern; var requested: u32=0;
 if operands[3]!=0 { let carrier=node(self,operands[3]); if carrier.tag!=Tag.function { let __cleanup_result_100_0: Id = 0; let __cleanup_result_100_1: bool = false; let __cleanup_result_100_2: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_53_0: Id = __cleanup_result_100_0; let __cleanup_result_53_1: bool = __cleanup_result_100_1; let __cleanup_result_53_2: Error = __cleanup_result_100_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_53_0, __cleanup_result_53_1, __cleanup_result_53_2; } requested=carrier.c; }
 for stage in 0..arity {
  if resolver.remaining==0 { let __cleanup_result_101_0: Id = 0; let __cleanup_result_101_1: bool = false; let __cleanup_result_101_2: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_54_0: Id = __cleanup_result_101_0; let __cleanup_result_54_1: bool = __cleanup_result_101_1; let __cleanup_result_54_2: Error = __cleanup_result_101_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_54_0, __cleanup_result_54_1, __cleanup_result_54_2; } resolver.remaining--; let arrow=source.node(required); if arrow.tag!=blot_check_types::Tag.function { let __cleanup_result_102_0: Id = 0; let __cleanup_result_102_1: bool = false; let __cleanup_result_102_2: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_55_0: Id = __cleanup_result_102_0; let __cleanup_result_55_1: bool = __cleanup_result_102_1; let __cleanup_result_55_2: Error = __cleanup_result_102_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_55_0, __cleanup_result_55_1, __cleanup_result_55_2; }
  if !matchDepth(work,arrow.a,operands[stage],0,resolver.remaining) { let __cleanup_result_103_0: Id = 0; let __cleanup_result_103_1: bool = false; let __cleanup_result_103_2: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_56_0: Id = __cleanup_result_103_0; let __cleanup_result_56_1: bool = __cleanup_result_103_1; let __cleanup_result_56_2: Error = __cleanup_result_103_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_56_0, __cleanup_result_56_1, __cleanup_result_56_2; }
  var projection=ProjectionWork<S,R> {self,source,mappingItems(mappings),mappingItems(rows),resolver}; var own_row=projectRowDepth(projection,arrow.c,0,resolver.remaining,false,null,null);
  if projection.failure==Error.unresolved_type {
   if operands[3]==0 { let __cleanup_result_104_0: Id = 0; let __cleanup_result_104_1: bool = false; let __cleanup_result_104_2: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_57_0: Id = __cleanup_result_104_0; let __cleanup_result_57_1: bool = __cleanup_result_104_1; let __cleanup_result_57_2: Error = __cleanup_result_104_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_57_0, __cleanup_result_57_1, __cleanup_result_57_2; } if !matchRowDepth(work,arrow.c,requested,0,resolver.remaining) { let __cleanup_result_105_0: Id = 0; let __cleanup_result_105_1: bool = false; let __cleanup_result_105_2: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_58_0: Id = __cleanup_result_105_0; let __cleanup_result_58_1: bool = __cleanup_result_105_1; let __cleanup_result_58_2: Error = __cleanup_result_105_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_58_0, __cleanup_result_58_1, __cleanup_result_58_2; }
   projection.failure=Error.none; projection.mappings=mappingItems(mappings); projection.rows=mappingItems(rows); own_row=projectRowDepth(projection,arrow.c,0,resolver.remaining,false,null,null);
  }
  if projection.failure!=Error.none { let __cleanup_result_106_0: Id = 0; let __cleanup_result_106_1: bool = false; let __cleanup_result_106_2: Error = projection.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_59_0: Id = __cleanup_result_106_0; let __cleanup_result_59_1: bool = __cleanup_result_106_1; let __cleanup_result_59_2: Error = __cleanup_result_106_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_59_0, __cleanup_result_59_1, __cleanup_result_59_2; }
  let own_labels=self.effects.view().rowLabels(own_row);
  for label,index in own_labels {
   if resolver.remaining==0 { let __cleanup_result_107_0: Id = 0; let __cleanup_result_107_1: bool = false; let __cleanup_result_107_2: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_60_0: Id = __cleanup_result_107_0; let __cleanup_result_60_1: bool = __cleanup_result_107_1; let __cleanup_result_60_2: Error = __cleanup_result_107_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_60_0, __cleanup_result_60_1, __cleanup_result_60_2; } resolver.remaining--; var count=0;
   for earlier in own_labels[..index+1] { if resolver.remaining==0 { let __cleanup_result_108_0: Id = 0; let __cleanup_result_108_1: bool = false; let __cleanup_result_108_2: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_61_0: Id = __cleanup_result_108_0; let __cleanup_result_61_1: bool = __cleanup_result_108_1; let __cleanup_result_61_2: Error = __cleanup_result_108_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_61_0, __cleanup_result_61_1, __cleanup_result_61_2; } resolver.remaining--; if earlier==label { count++; } }
   if operands[3]!=0 { var available=0; for actual in self.effects.view().rowLabels(requested) { if resolver.remaining==0 { let __cleanup_result_109_0: Id = 0; let __cleanup_result_109_1: bool = false; let __cleanup_result_109_2: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_62_0: Id = __cleanup_result_109_0; let __cleanup_result_62_1: bool = __cleanup_result_109_1; let __cleanup_result_62_2: Error = __cleanup_result_109_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_62_0, __cleanup_result_62_1, __cleanup_result_62_2; } resolver.remaining--; if actual==label { available++; } } if count>available { let __cleanup_result_110_0: Id = 0; let __cleanup_result_110_1: bool = false; let __cleanup_result_110_2: Error = Error.type_mismatch; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_63_0: Id = __cleanup_result_110_0; let __cleanup_result_63_1: bool = __cleanup_result_110_1; let __cleanup_result_63_2: Error = __cleanup_result_110_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_63_0, __cleanup_result_63_1, __cleanup_result_63_2; } }
   var present=0; for actual in labels.items { if resolver.remaining==0 { let __cleanup_result_111_0: Id = 0; let __cleanup_result_111_1: bool = false; let __cleanup_result_111_2: Error = Error.evidence_limit; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_64_0: Id = __cleanup_result_111_0; let __cleanup_result_64_1: bool = __cleanup_result_111_1; let __cleanup_result_64_2: Error = __cleanup_result_111_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_64_0, __cleanup_result_64_1, __cleanup_result_64_2; } resolver.remaining--; if actual==label { present++; } } if count>present { labels.push(label); }
  }
  required=arrow.b;
 }
 if !matchDepth(work,required,operands[2],0,resolver.remaining) { if work.failure!=Error.none { let __cleanup_result_112_0: Id = 0; let __cleanup_result_112_1: bool = false; let __cleanup_result_112_2: Error = work.failure; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_65_0: Id = __cleanup_result_112_0; let __cleanup_result_65_1: bool = __cleanup_result_112_1; let __cleanup_result_65_2: Error = __cleanup_result_112_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_65_0, __cleanup_result_65_1, __cleanup_result_65_2; } let __cleanup_result_113_0: Id = 0; let __cleanup_result_113_1: bool = false; let __cleanup_result_113_2: Error = Error.type_mismatch; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_66_0: Id = __cleanup_result_113_0; let __cleanup_result_66_1: bool = __cleanup_result_113_1; let __cleanup_result_66_2: Error = __cleanup_result_113_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_66_0, __cleanup_result_66_1, __cleanup_result_66_2; }
 accepted=true; if operands[3]!=0 { let __cleanup_result_114_0: Id = operands[3]; let __cleanup_result_114_1: bool = true; let __cleanup_result_114_2: Error = Error.none; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_67_0: Id = __cleanup_result_114_0; let __cleanup_result_67_1: bool = __cleanup_result_114_1; let __cleanup_result_67_2: Error = __cleanup_result_114_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_67_0, __cleanup_result_67_1, __cleanup_result_67_2; }
 let own,err=self.effects.internRow(labels.items); if err!=Error.none { let __cleanup_result_115_0: Id = 0; let __cleanup_result_115_1: bool = false; let __cleanup_result_115_2: Error = err; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_68_0: Id = __cleanup_result_115_0; let __cleanup_result_68_1: bool = __cleanup_result_115_1; let __cleanup_result_68_2: Error = __cleanup_result_115_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_68_0, __cleanup_result_68_1, __cleanup_result_68_2; } let id,error=internWithEffects(self,Tag.function,1,1,own,[]); let __cleanup_result_116_0: Id = id; let __cleanup_result_116_1: bool = error==Error.none; let __cleanup_result_116_2: Error = error; { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } } let __cleanup_result_69_0: Id = __cleanup_result_116_0; let __cleanup_result_69_1: bool = __cleanup_result_116_1; let __cleanup_result_69_2: Error = __cleanup_result_116_2; labels.deinit(); work.memo.deinit(); return __cleanup_result_69_0, __cleanup_result_69_1, __cleanup_result_69_2;
 { if !accepted { mappings.resize(frontier); rows.resize(row_frontier); } }  labels.deinit(); work.memo.deinit(); }
struct SnapshotTables { nodes: Node[>..]&,extra: Id[>..]&,quantifier_goals: QuantifierGoals[>..]&,quantifier_obligations: Goal[>..]&,effects: blot_check_effect_evidence::SnapshotTables }
fn copyOwned(self: const Store&,target: SnapshotTables) -> Snapshot,Error {
 let ns=target.nodes.len; let es=target.extra.len; let gs=target.quantifier_goals.len; let os=target.quantifier_obligations.len;
 target.nodes.append(self.nodes.items); target.extra.append(self.extra.items); target.quantifier_goals.append(self.quantifier_goals.items); target.quantifier_obligations.append(self.quantifier_obligations.items);
 let effects,err=self.effects.copyOwned(target.effects); if err!=Error.none { return default<Snapshot>(),err; }
 return Snapshot {nodes:target.nodes[ns..],extra:target.extra[es..],effects:effects,quantifier_goals:target.quantifier_goals[gs..],quantifier_obligations:target.quantifier_obligations[os..]},Error.none;
}
fn clone(self: const Store&,destination: Store&) -> Error {
 if self.owner_id==destination.owner_id||!valid(self)||!valid(destination) { return Error.type_mismatch; }
 destination.nodes.clear(); destination.nodes.append(self.nodes.items);
 destination.extra.clear(); destination.extra.append(self.extra.items);
 destination.next.clear(); destination.next.append(self.next.items);
 destination.quantifier_goals.clear(); destination.quantifier_goals.append(self.quantifier_goals.items);
 destination.quantifier_obligations.clear(); destination.quantifier_obligations.append(self.quantifier_obligations.items);
 destination.projection_owners.clear(); destination.projection_quantifiers.clear(); copyBuckets(destination.buckets,self.buckets);
 let effects,error=blot_check_effect_evidence::clone(self.effects); if error!=Error.none { return error; } destination.effects.deinit(); destination.effects=effects; return Error.none;
}
fn withStore<C,F>(context: C&) -> Error { let initialized,error=init(); if error!=Error.none { return error; } var store=initialized; let result=F(context,store); deinit(store); return result; }
fn withPooledStore<C,F>(context: C&) -> Error { return withStore<C,F>(context); }
fn withStoreValue<C,F,R>(context: C&) -> R,Error { let initialized,error=init(); if error!=Error.none { return default<R>(),error; } var store=initialized; let result,failure=F(context,store); deinit(store); return result,failure; }
fn withPooledStoreValue<C,F,R>(context: C&) -> R,Error { return withStoreValue<C,F,R>(context); }
fn deinit(self: Store&) { if self.lease==0 { return; } assert(valid(self));
 self.nodes.deinit();
 self.extra.deinit();
 self.next.deinit();
 self.buckets.deinit();
 self.projection_owners.deinit();
 self.projection_quantifiers.deinit();
 self.quantifier_goals.deinit();
 self.quantifier_obligations.deinit();
 self.effects.deinit(); let index=self.lease-1; states[index].owner_id=0; states.free(index); self=Store {};
}
fn prepareCommit(source: const Store&,destination: Store&) -> Error { if !valid(source)||!valid(destination)||source.owner_id==destination.owner_id { return Error.type_mismatch; }
 if source.nodes.failure!=Error.none { return source.nodes.failure; }
 if source.extra.failure!=Error.none { return source.extra.failure; }
 if source.next.failure!=Error.none { return source.next.failure; }
 if source.projection_owners.failure!=Error.none { return source.projection_owners.failure; }
 if source.projection_quantifiers.failure!=Error.none { return source.projection_quantifiers.failure; }
 if source.quantifier_goals.failure!=Error.none { return source.quantifier_goals.failure; }
 if source.quantifier_obligations.failure!=Error.none { return source.quantifier_obligations.failure; }
 return blot_check_effect_evidence::prepareCommit(source.effects,destination.effects); }
// Publication moves typed capacity runs; old destination storage is reclaimed.
fn commit(source: Store&,destination: Store&) { assert(valid(source)&&valid(destination)&&source.owner_id!=destination.owner_id);
 destination.nodes.deinit(); destination.nodes=source.nodes; source.nodes=NodeBuffer {};
 destination.extra.deinit(); destination.extra=source.extra; source.extra=WordBuffer {};
 destination.next.deinit(); destination.next=source.next; source.next=WordBuffer {};
 destination.buckets.deinit(); destination.buckets=source.buckets; source.buckets=Buckets {};
 destination.projection_owners.deinit(); destination.projection_owners=source.projection_owners; source.projection_owners=OwnersBuffer {};
 destination.projection_quantifiers.deinit(); destination.projection_quantifiers=source.projection_quantifiers; source.projection_quantifiers=WordBuffer {};
 destination.quantifier_goals.deinit(); destination.quantifier_goals=source.quantifier_goals; source.quantifier_goals=QuantifierBuffer {};
 destination.quantifier_obligations.deinit(); destination.quantifier_obligations=source.quantifier_obligations; source.quantifier_obligations=GoalBuffer {};
 blot_check_effect_evidence::commit(source.effects,destination.effects); let identity=destination.owner_id; destination.owner_id=source.owner_id; states[destination.lease-1].owner_id=destination.owner_id; source.owner_id=identity; states[source.lease-1].owner_id=source.owner_id;
}

struct ByteBuffer { storage: u8[:]=[],items: u8[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ByteBuffer: u8[>..]=[];
fn ensure(self: ByteBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ByteBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ByteBuffer&,value: u8) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ByteBuffer); self.len=self.items.len; }
fn append(self: ByteBuffer&,values: const u8[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ByteBuffer); self.len=self.items.len; }
fn resize(self: ByteBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ByteBuffer&,length: i64,value: u8) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ByteBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ByteBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ByteBuffer); self.len=0; self.failure=Error.none; }
struct BoolBuffer { storage: bool[:]=[],items: bool[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_BoolBuffer: bool[>..]=[];
fn ensure(self: BoolBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_BoolBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: BoolBuffer&,value: bool) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_BoolBuffer); self.len=self.items.len; }
fn append(self: BoolBuffer&,values: const bool[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_BoolBuffer); self.len=self.items.len; }
fn resize(self: BoolBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: BoolBuffer&,length: i64,value: bool) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: BoolBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: BoolBuffer&) { blot_support_pooled_buffer::deinit(self,pool_BoolBuffer); self.len=0; self.failure=Error.none; }
struct MappingBuffer { storage: Mapping[:]=[],items: Mapping[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_MappingBuffer: Mapping[>..]=[];
fn ensure(self: MappingBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_MappingBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: MappingBuffer&,value: Mapping) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_MappingBuffer); self.len=self.items.len; }
fn append(self: MappingBuffer&,values: const Mapping[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_MappingBuffer); self.len=self.items.len; }
fn resize(self: MappingBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: MappingBuffer&,length: i64,value: Mapping) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: MappingBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: MappingBuffer&) { blot_support_pooled_buffer::deinit(self,pool_MappingBuffer); self.len=0; self.failure=Error.none; }
struct RowMappingBuffer { storage: RowMapping[:]=[],items: RowMapping[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RowMappingBuffer: RowMapping[>..]=[];
fn ensure(self: RowMappingBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RowMappingBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RowMappingBuffer&,value: RowMapping) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RowMappingBuffer); self.len=self.items.len; }
fn append(self: RowMappingBuffer&,values: const RowMapping[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RowMappingBuffer); self.len=self.items.len; }
fn resize(self: RowMappingBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: RowMappingBuffer&,length: i64,value: RowMapping) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: RowMappingBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RowMappingBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RowMappingBuffer); self.len=0; self.failure=Error.none; }
struct PooledMappingsHeader { buffer: MappingBuffer=MappingBuffer {},generation: u64=0,live: bool=false }
reusable var mapping_headers: PooledMappingsHeader[>..]=[];
var inactive_mapping_header: MappingBuffer=MappingBuffer {};
var next_mapping_generation: u64=1;
struct PooledMappings { header: MappingBuffer&=inactive_mapping_header,items: (Mapping[:])&=inactive_mapping_header.items,len: i64&=inactive_mapping_header.len,failure: Error&=inactive_mapping_header.failure,lease: u32=0,generation: u64=0 }
fn activate(self: PooledMappings&) -> Error { if self.lease!=0 { assert(self.lease-1<mapping_headers.len&&mapping_headers[self.lease-1].live&&mapping_headers[self.lease-1].generation==self.generation); return Error.none; } if next_mapping_generation==0xffffffffffffffff||mapping_headers.len>=0xffffffff { return Error.out_of_memory; } let generation=next_mapping_generation; next_mapping_generation++; let index=mapping_headers.alloc_index(PooledMappingsHeader {generation:generation,live:true}); let header: MappingBuffer&=mapping_headers[index].buffer; self.header .= header; self.items .= header.items; self.len .= header.len; self.failure .= header.failure; self.lease=(index+1) as u32; self.generation=generation; return Error.none; }
fn push(self: PooledMappings&,value: Mapping) { let error=activate(self); if error!=Error.none { self.failure=error; return; } self.header.push(value); }
fn append(self: PooledMappings&,values: const Mapping[:]) { let error=activate(self); if error!=Error.none { self.failure=error; return; } self.header.append(values); }
fn resize(self: PooledMappings&,length: i64) { assert(self.lease!=0||length==0); if self.lease!=0 { self.header.resize(length); } }
fn clear(self: PooledMappings&) { if self.lease!=0 { self.header.clear(); } }
fn deinit(self: PooledMappings&) { if self.lease==0 { return; } let error=activate(self); assert(error==Error.none); self.header.deinit(); let index=self.lease-1; mapping_headers[index].live=false; mapping_headers.free(index); self=PooledMappings {}; }
fn mappingItems(self: PooledMappings) -> const Mapping[:] { return self.items; }
struct PooledRowsHeader { buffer: RowMappingBuffer=RowMappingBuffer {},generation: u64=0,live: bool=false }
reusable var row_mapping_headers: PooledRowsHeader[>..]=[];
var inactive_row_mapping_header: RowMappingBuffer=RowMappingBuffer {};
var next_row_mapping_generation: u64=1;
struct PooledRows { header: RowMappingBuffer&=inactive_row_mapping_header,items: (RowMapping[:])&=inactive_row_mapping_header.items,len: i64&=inactive_row_mapping_header.len,failure: Error&=inactive_row_mapping_header.failure,lease: u32=0,generation: u64=0 }
fn activate(self: PooledRows&) -> Error { if self.lease!=0 { assert(self.lease-1<row_mapping_headers.len&&row_mapping_headers[self.lease-1].live&&row_mapping_headers[self.lease-1].generation==self.generation); return Error.none; } if next_row_mapping_generation==0xffffffffffffffff||row_mapping_headers.len>=0xffffffff { return Error.out_of_memory; } let generation=next_row_mapping_generation; next_row_mapping_generation++; let index=row_mapping_headers.alloc_index(PooledRowsHeader {generation:generation,live:true}); let header: RowMappingBuffer&=row_mapping_headers[index].buffer; self.header .= header; self.items .= header.items; self.len .= header.len; self.failure .= header.failure; self.lease=(index+1) as u32; self.generation=generation; return Error.none; }
fn push(self: PooledRows&,value: RowMapping) { let error=activate(self); if error!=Error.none { self.failure=error; return; } self.header.push(value); }
fn append(self: PooledRows&,values: const RowMapping[:]) { let error=activate(self); if error!=Error.none { self.failure=error; return; } self.header.append(values); }
fn resize(self: PooledRows&,length: i64) { assert(self.lease!=0||length==0); if self.lease!=0 { self.header.resize(length); } }
fn clear(self: PooledRows&) { if self.lease!=0 { self.header.clear(); } }
fn deinit(self: PooledRows&) { if self.lease==0 { return; } let error=activate(self); assert(error==Error.none); self.header.deinit(); let index=self.lease-1; row_mapping_headers[index].live=false; row_mapping_headers.free(index); self=PooledRows {}; }
fn mappingItems(self: PooledRows) -> const RowMapping[:] { return self.items; }
type MatchMemo=blot_support_pooled_map::Map<u64,bool>;
reusable[] var match_memo_slots: dictionary_slot<u64,bool>[>..]=[];
fn contains(self: const MatchMemo&,key: u64) -> bool { return blot_support_pooled_map::contains(self,key); }
fn insert(self: MatchMemo&,key: u64,value: bool) { blot_support_pooled_map::insert(self,key,value,match_memo_slots); }
fn clear(self: MatchMemo&) { blot_support_pooled_map::clear(self); }
fn deinit(self: MatchMemo&) { blot_support_pooled_map::deinit(self,match_memo_slots); }
fn mappingItems(self: Mapping[>..<]&) -> const Mapping[:] { return self; }
fn mappingItems(self: RowMapping[>..<]&) -> const RowMapping[:] { return self; }

fn matchWithRowsBudget<S>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,budget: i64&) -> bool,Error { return matchWithRowsBudgetInner<S,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, actual, mappings, rows, budget); }
fn matchWithRowsBudget<S>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,budget: i64&) -> bool,Error { let first=activate(mappings); if first!=Error.none { return false,first; } let second=activate(rows); if second!=Error.none { return false,second; } return matchWithRowsBudgetInner<S,PooledMappings,PooledRows>(self, source, pattern, actual, mappings, rows, budget); }
fn matchWithRows<S>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&) -> bool,Error { return matchWithRowsInner<S,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, actual, mappings, rows); }
fn matchWithRows<S>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&) -> bool,Error { let first=activate(mappings); if first!=Error.none { return false,first; } let second=activate(rows); if second!=Error.none { return false,second; } return matchWithRowsInner<S,PooledMappings,PooledRows>(self, source, pattern, actual, mappings, rows); }
fn matchSelected<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> bool,Error { return matchSelectedInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, actual, mappings, rows, resolver); }
fn matchSelected<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> bool,Error { let first=activate(mappings); if first!=Error.none { return false,first; } let second=activate(rows); if second!=Error.none { return false,second; } return matchSelectedInner<S,R,PooledMappings,PooledRows>(self, source, pattern, actual, mappings, rows, resolver); }
fn matchSignature<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&,infer_rows: bool) -> bool,Error { return matchSignatureInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, actual, mappings, rows, resolver, infer_rows); }
fn matchSignature<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&,infer_rows: bool) -> bool,Error { let first=activate(mappings); if first!=Error.none { return false,first; } let second=activate(rows); if second!=Error.none { return false,second; } return matchSignatureInner<S,R,PooledMappings,PooledRows>(self, source, pattern, actual, mappings, rows, resolver, infer_rows); }
fn matchTemplate<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> bool,Error { return matchTemplateInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, actual, mappings, rows, resolver); }
fn matchTemplate<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> bool,Error { let first=activate(mappings); if first!=Error.none { return false,first; } let second=activate(rows); if second!=Error.none { return false,second; } return matchTemplateInner<S,R,PooledMappings,PooledRows>(self, source, pattern, actual, mappings, rows, resolver); }
fn matchLegacySignature<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> bool,Error { return matchLegacySignatureInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, actual, mappings, rows, resolver); }
fn matchLegacySignature<S,R>(self: Store,source: const S&,pattern: u32,actual: Id,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> bool,Error { let first=activate(mappings); if first!=Error.none { return false,first; } let second=activate(rows); if second!=Error.none { return false,second; } return matchLegacySignatureInner<S,R,PooledMappings,PooledRows>(self, source, pattern, actual, mappings, rows, resolver); }
fn matchPrerequisite<S,R>(self: Store,source: const S&,pattern: u32,operands: Id[4],arity: i64,mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: ProjectionResolver<R>&) -> Id,bool,Error { return matchPrerequisiteInner<S,R,Mapping[>..<]&,RowMapping[>..<]&>(self, source, pattern, operands, arity, mappings, rows, resolver); }
fn matchPrerequisite<S,R>(self: Store,source: const S&,pattern: u32,operands: Id[4],arity: i64,mappings: PooledMappings&,rows: PooledRows&,resolver: ProjectionResolver<R>&) -> Id,bool,Error { let first=activate(mappings); if first!=Error.none { return 0,false,first; } let second=activate(rows); if second!=Error.none { return 0,false,second; } return matchPrerequisiteInner<S,R,PooledMappings,PooledRows>(self, source, pattern, operands, arity, mappings, rows, resolver); }

fn mappingFailure(self: Mapping[>..<]&) -> Error { return Error.none; }
fn mappingFailure(self: RowMapping[>..<]&) -> Error { return Error.none; }
fn mappingFailure(self: PooledMappings) -> Error { return self.failure; }
fn mappingFailure(self: PooledRows) -> Error { return self.failure; }
