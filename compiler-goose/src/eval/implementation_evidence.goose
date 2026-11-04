// Complete selected semantic proofs. No body evaluation or captured values.
namespace blot_eval_implementation_evidence;
import std;
import dictionary;
import check.types;
import check.core;
import check.check;
import backend.runtime_identity;
import reuse.dispatch_explanation;
import .type_evidence;
import .implementation_trace;
import .implementation_predicates;
import .implementation_rows;
import parse.symbols;
import support.error;
import support.option;
import support.native;
type Error=blot_error::Error;
type Identity=blot_check_types::NominalIdentity;
type List=blot_check_types::List;
type Mapping=blot_eval_type_evidence::Mapping;
type RowMapping=blot_eval_type_evidence::RowMapping;
type Tag=blot_eval_type_evidence::Tag;
type K=blot_check_types::ObligationKind;
type Outcome=blot_reuse_dispatch_explanation::Outcome;
enum Code { missing_implementation,incompatible_implementation,recursive_evidence,recursive_associated_type,associated_limit }
enum ProofKind { implementation,predicate }
struct Member { name: u32,kind: blot_check_core::ImplementationMemberKind=blot_check_core::ImplementationMemberKind.type_,root: u32,target: blot_check_core::BindingRef }
struct LegacyChoice { target: blot_check_core::BindingRef,carrier: u32=0 }
struct Fact { kind: K=K.type_rep,operator: blot_check_types::Operator=blot_check_types::Operator.none,identity: Identity=Identity {0,0},name: u32=0,operands: u32[4]=[0;4],target: blot_check_core::BindingRef=blot_check_core::BindingRef {0,0} }
struct Proof { kind: ProofKind=ProofKind.implementation,predicate: Fact=Fact {},context: u32,implementation: Identity,contract: Identity,arguments: List,members: List,prerequisites: List }
struct View { owner_id: u64=0,proofs: const Proof[:]=[],arguments: const u32[:]=[],members: const Member[:]=[],edges: const u32[:]=[] }
struct Snapshot { owner_id: u64=blot_native::fresh_owner_id(),proofs: const Proof[:]=[],arguments: const u32[:]=[],members: const Member[:]=[],edges: const u32[:]=[] }
fn view(self: const Snapshot&) -> View { return View {self.owner_id,self.proofs,self.arguments,self.members,self.edges}; }
struct FactKey { context: u32,fact: Fact }
fn hash(key: FactKey) -> u64 { var h=::hash(key.context); h=::hash_combine(h,blot_check_types::obligationKindCode(key.fact.kind) as u64); h=::hash_combine(h,blot_check_types::operatorCode(key.fact.operator) as u64); h=::hash_combine(h,::hash(key.fact.identity.unit)); h=::hash_combine(h,::hash(key.fact.identity.decl)); h=::hash_combine(h,::hash(key.fact.name)); for value in key.fact.operands { h=::hash_combine(h,::hash(value)); } return ::hash_combine(::hash_combine(h,::hash(key.fact.target.unit)),::hash(key.fact.target.binding)); }
struct Active { context: u32,contract: Identity,arguments: List }
struct ActiveProjection { context: u32,contract: Identity,member: u32,arguments: List }
struct Provisional { context: u32,declaration: blot_check_core::Implementation,arguments: List,mappings: List,rows: List }
struct Tables { proofs: Proof[>..<]&,arguments: u32[>..<]&,members: Member[>..<]&,edges: u32[>..<]&,active_arguments: u32[>..<]&,active: Active[>..<]&,active_projections: ActiveProjection[>..<]&,provisional_equations: Provisional[>..<]&,provisional_mappings: Mapping[>..<]&,provisional_rows: RowMapping[>..<]&,buckets: dictionary<u64,u32>&,next: u32[>..<]&,facts: dictionary<FactKey,u32>&,active_facts: FactKey[>..<]& }
struct Store { owner_id: u64=blot_native::fresh_owner_id(),proofs: Proof[>..<]&,arguments: u32[>..<]&,members: Member[>..<]&,edges: u32[>..<]&,active_arguments: u32[>..<]&,active: Active[>..<]&,active_projections: ActiveProjection[>..<]&,provisional_equations: Provisional[>..<]&,provisional_mappings: Mapping[>..<]&,provisional_rows: RowMapping[>..<]&,buckets: dictionary<u64,u32>&,next: u32[>..<]&,facts: dictionary<FactKey,u32>&,active_facts: FactKey[>..<]&,trace: blot_eval_implementation_trace::Record=blot_eval_implementation_trace::Record {},failure: blot_support::Option<Code>=blot_support::none<Code>(),candidates: u64=0,prerequisite_edges: u64=0,hits: u64=0,max_depth: i64=0 }
fn init(t: Tables) -> Store { return Store {proofs:t.proofs,arguments:t.arguments,members:t.members,edges:t.edges,active_arguments:t.active_arguments,active:t.active,active_projections:t.active_projections,provisional_equations:t.provisional_equations,provisional_mappings:t.provisional_mappings,provisional_rows:t.provisional_rows,buckets:t.buckets,next:t.next,facts:t.facts,active_facts:t.active_facts}; }
fn view(self: const Store&) -> View { return View {self.owner_id,self.proofs,self.arguments,self.members,self.edges}; }
struct SnapshotTables { proofs: Proof[>..]&,arguments: u32[>..]&,members: Member[>..]&,edges: u32[>..]& }
fn copyOwned(self: const Store&,target: SnapshotTables) -> Snapshot,Error { let p=target.proofs.len; let a=target.arguments.len; let m=target.members.len; let e=target.edges.len; target.proofs.append(self.proofs); target.arguments.append(self.arguments); target.members.append(self.members); target.edges.append(self.edges); return Snapshot {proofs:target.proofs[p..],arguments:target.arguments[a..],members:target.members[m..],edges:target.edges[e..]},Error.none; }
struct Work<H> { store: Store&,host: H&,error: Error=Error.none }
fn fail<H>(w: Work<H>&,error: Error) -> u32 { if w.error==Error.none { w.error=error; } return 0; }
fn take<H>(w: Work<H>&,value: u32,error: Error) -> u32 { if error!=Error.none { return fail(w,error); } return value; }
fn step<H>(w: Work<H>&) -> bool {
 if w.error!=Error.none { return false; } if w.host.associated_remaining==0 { w.store.failure=blot_support::some(Code.associated_limit); for i in 0..w.store.trace.len { if w.store.trace.candidates[i].outcome==Outcome.selected { w.store.trace.candidates[i].outcome=Outcome.limit; } } fail(w,Error.associated_limit); return false; } w.host.associated_remaining--; return true;
}
fn owner<H>(host: H&,unit: u32) -> i64 { for module,index in host.units { var identity=module.unit; if identity==0 { identity=(index+1) as u32; } if identity==unit { return index; } } return -1; }
fn canonicalLess<H>(host: H&,left: blot_check_core::Implementation,right: blot_check_core::Implementation) -> bool {
 let identity=host.diagnosticIdentity();
 if identity.present { let before=identity.value.owner(left.identity.unit); let after=identity.value.owner(right.identity.unit); if before.present&&after.present&&before.value!=after.value { return before.value<after.value; } }
 if left.identity.unit!=right.identity.unit { return left.identity.unit<right.identity.unit; }
 if left.origin_span.present&&right.origin_span.present&&left.origin_span.value.start!=right.origin_span.value.start { return left.origin_span.value.start<right.origin_span.value.start; }
 if identity.present { let before=identity.value.symbol(left.name); let after=identity.value.symbol(right.name); if before.present&&after.present { return before.value<after.value; } } return left.identity.decl<right.identity.decl;
}
fn key(context: u32,contract: Identity,arguments: const u32[:]) -> u64 { var bytes: u8[>..<]=[]; blot_eval_type_evidence::put32(bytes,context); blot_eval_type_evidence::put32(bytes,contract.unit); blot_eval_type_evidence::put32(bytes,contract.decl); for arg in arguments { blot_eval_type_evidence::put32(bytes,arg); } return blot_parse_symbols::wyhash(bytes); }
fn sameArguments(self: const Store&,span: List,arguments: const u32[:]) -> bool { return span.len==arguments.len&&self.arguments[span.start..span.start+span.len]==arguments; }
fn sameActiveArguments(self: const Store&,span: List,arguments: const u32[:]) -> bool { return span.len==arguments.len&&self.active_arguments[span.start..span.start+span.len]==arguments; }
fn depthAvailable(self: const Store&) -> bool { if self.active.len>=256 { return false; } let remaining=256-self.active.len; if self.active_projections.len>=remaining { return false; } return self.active_facts.len<remaining-self.active_projections.len; }
struct Mark { proofs: i64,arguments: i64,members: i64,edges: i64 }
fn mark(self: const Store&) -> Mark { return Mark {self.proofs.len,self.arguments.len,self.members.len,self.edges.len}; }
fn rollback(self: Store&,point: Mark) {
 var erase: FactKey[>..]=[]; for slot in self.facts.slots { if slot.tag!=0&&slot.val>=point.proofs { erase.push(slot.key); } } for key in erase { self.facts.remove(key); }
 var keys: u64[>..]=[]; for slot in self.buckets.slots { if slot.tag!=0 { keys.push(slot.key); } }
 for key in keys { let known=self.buckets.get(key); var head: u32=0; if known { head=known; } while head!=0&&head-1>=point.proofs { head=self.next[head-1]; } if head==0 { self.buckets.remove(key); } else { self.buckets.insert(key,head); } }
 self.next.resize(point.proofs); self.proofs.resize(point.proofs); self.arguments.resize(point.arguments); self.members.resize(point.members); self.edges.resize(point.edges);
}
fn saveActive(self: Store&,arguments: const u32[:]) -> List { let start=self.active_arguments.len; self.active_arguments.append(arguments); return List {start as u32,arguments.len as u32}; }
fn saveArguments(self: Store&,arguments: const u32[:]) -> List { let start=self.arguments.len; self.arguments.append(arguments); return List {start as u32,arguments.len as u32}; }
struct ProjectionContext<H> { host: H&,store: Store&,context: u32 }
fn resolve<H>(self: ProjectionContext<H>&,contract: Identity,member: u32,arguments: const u32[:]) -> u32,Error {
 let id,error=projection(self.store,self.host,self.context,contract,member,arguments); if error==Error.associated_limit { return 0,Error.evidence_limit; } if error==Error.out_of_memory||error==Error.unresolved_type||error==Error.none { return id,error; } return 0,Error.type_mismatch;
}
fn resolver<H>(self: ProjectionContext<H>&) -> blot_eval_type_evidence::ProjectionResolver<ProjectionContext<H>> { return blot_eval_type_evidence::ProjectionResolver<ProjectionContext<H>> {self,self.host.associated_remaining,true}; }
fn unrestrictedAssociatedNode<H>(host: H&,root: u32,depth: i64,completed: dictionary<u32,u8>&) -> u8,Error {
 if depth>=128||host.associated_remaining==0 { return 0,Error.associated_limit; } host.associated_remaining--; let known=completed.get(root); if known { if depth+known>128 { return 0,Error.associated_limit; } return known,Error.none; }
 let node=host.evidenceStore().node(root); if node.tag==Tag.usage { return 0,Error.type_mismatch; }
 if node.tag==Tag.nominal { for module in host.units { for nominal in module.nominals { if host.associated_remaining==0 { return 0,Error.associated_limit; } host.associated_remaining--; if nominal.identity.unit==node.a&&nominal.identity.decl==node.b&&nominal.has_usage { return 0,Error.type_mismatch; } } } }
 var height: u8=1; var children: u32[>..]=[];
 if node.tag==Tag.function { children.append([node.a,node.b]); }
 else if node.tag==Tag.array||node.tag==Tag.list||node.tag==Tag.cursor||node.tag==Tag.resolver||node.tag==Tag.provider||node.tag==Tag.state_provider||node.tag==Tag.scoped { children.push(node.a); }
 else if node.tag==Tag.product||node.tag==Tag.nominal||node.tag==Tag.projection { children.append(host.evidenceStore().children(root)); }
 else if node.tag==Tag.record { let fields=host.evidenceStore().children(root); var index=1; while index<fields.len { children.push(fields[index]); index+=2; } }
 else if node.tag==Tag.forall||node.tag==Tag.existential { children.push(node.a); for goal in host.evidenceStore().view().quantifierGoals(root) { children.append([goal.ty,goal.other,goal.result,goal.signature]); } }
 for child in children { let h,error=unrestrictedAssociatedNode(host,child,depth+1,completed); if error!=Error.none { return 0,error; } if height<h+1 { height=h+1; } } completed.insert(root,height); return height,Error.none;
}
fn unrestrictedAssociatedType<H>(host: H&,root: u32,depth: i64) -> Error { var completed: dictionary<u32,u8>; let height,error=unrestrictedAssociatedNode(host,root,depth,completed); return error; }
fn rejectedPrerequisite<H>(w: Work<H>&,error: Error,identity: Identity,traced: i64,kind: K) -> u32 {
 if error==Error.out_of_memory { return fail(w,error); }
 if w.store.failure.present&&(w.store.failure.value==Code.recursive_evidence||w.store.failure.value==Code.recursive_associated_type) { return fail(w,error); }
 if error==Error.associated_limit||error==Error.evidence_limit||(w.store.failure.present&&w.store.failure.value==Code.associated_limit) { w.store.failure=blot_support::some(Code.associated_limit); w.store.trace.candidate(identity,Outcome.limit); w.store.trace.setOutcome(traced,traced>=0,Outcome.limit); return fail(w,Error.associated_limit); }
 w.store.failure=blot_support::some(Code.incompatible_implementation); w.store.trace.candidate(identity,Outcome.requires_evidence); w.store.trace.setOutcome(traced,traced>=0,blot_eval_implementation_predicates::failureOutcome(kind)); return fail(w,Error.incompatible_implementation);
}
fn projection<H>(self: Store&,host: H&,context: u32,contract: Identity,member_name: u32,input: const u32[:]) -> u32,Error { var work=Work<H> {self,host}; let result=projectionInner(work,context,contract,member_name,input); return result,work.error; }
fn projectionInner<H>(w: Work<H>&,context: u32,contract: Identity,member_name: u32,input: const u32[:]) -> u32 {
 if w.error!=Error.none { return 0; } let self=w.store; let host=w.host; let point=mark(self); var success=false; defer { if !success { rollback(self,point); } }
 if self.active.len==0&&self.active_projections.len==0&&self.active_facts.len==0 { self.failure=blot_support::none<Code>(); self.trace=blot_eval_implementation_trace::Record {context:context,contract:contract}; }
 var arguments: u32[>..]=[]; arguments.append(input); if !step(w) { return 0; } if !depthAvailable(self) { self.failure=blot_support::some(Code.associated_limit); return fail(w,Error.associated_limit); }
 for active in self.active_projections { if active.context==context&&active.contract==contract&&active.member==member_name&&sameActiveArguments(self,active.arguments,arguments) { self.failure=blot_support::some(Code.recursive_associated_type); return fail(w,Error.incompatible_implementation); } }
 let saved=saveActive(self,arguments); self.active_projections.push(ActiveProjection {context,contract,member_name,saved}); defer { self.active_projections.resize(self.active_projections.len-1); self.active_arguments.resize(saved.start); }
 let owner_id=owner(host,context); if owner_id<0 { return fail(w,Error.type_mismatch); } let module=host.units[owner_id];
 for definition in module.contracts {
  if definition.identity!=contract { continue; }
  for descriptor in module.contract_members[definition.members.start..definition.members.start+definition.members.len] {
   if descriptor.name!=member_name { continue; }
   if descriptor.kind==blot_check_core::ContractMemberKind.defined_type {
    var mappings: Mapping[>..<]=[]; var rows: RowMapping[>..<]=[]; if arguments.len!=definition.parameters.len { return fail(w,Error.type_mismatch); }
    for pattern,index in module.types.list(definition.parameters) { let matched,error=host.evidenceStore().matchWithRowsBudget(module.types,pattern,arguments[index],mappings,rows,host.associated_remaining); if error!=Error.none { return fail(w,error); } if !matched { return fail(w,Error.type_mismatch); } }
    var state=ProjectionContext<H> {host,self,context}; var resolver_=resolver(state); let result,error=host.evidenceStore().projectSelected(module.types,descriptor.root,mappings,rows,resolver_);
    if error==Error.evidence_limit { return fail(w,Error.associated_limit); } if error!=Error.none { return fail(w,error); } let err=unrestrictedAssociatedType(host,result,0); if err!=Error.none { return fail(w,err); } success=true; return result;
   }
   var provisional=self.provisional_equations.len;
   while provisional!=0 { provisional--; let frame=self.provisional_equations[provisional]; if frame.context!=context||frame.declaration.contract!=contract||!sameActiveArguments(self,frame.arguments,arguments) { continue; }
    for member in module.implementation_members[frame.declaration.members.start..frame.declaration.members.start+frame.declaration.members.len] {
     if member.name!=member_name||member.kind!=blot_check_core::ImplementationMemberKind.type_ { continue; }
     var state=ProjectionContext<H> {host,self,context}; var resolver_=resolver(state); let mappings=self.provisional_mappings[frame.mappings.start..frame.mappings.start+frame.mappings.len]; let rows=self.provisional_rows[frame.rows.start..frame.rows.start+frame.rows.len];
     let result,error=host.evidenceStore().projectSelected(module.types,member.root,mappings,rows,resolver_); if error!=Error.none { return fail(w,error); } let err=unrestrictedAssociatedType(host,result,0); if err!=Error.none { return fail(w,err); } success=true; return result;
    }
   }
   let proof=resolveInner(w,context,contract,arguments); if w.error!=Error.none { return 0; }
   let members=self.proofs[proof].members; for member in self.members[members.start..members.start+members.len] { if member.name==member_name { success=true; return member.root; } } return fail(w,Error.type_mismatch);
  }
  return fail(w,Error.type_mismatch);
 }
 return fail(w,Error.type_mismatch);
}
fn resolve<H>(self: Store&,host: H&,context: u32,contract: Identity,input: const u32[:]) -> u32,Error { var work=Work<H> {self,host}; let result=resolveInner(work,context,contract,input); return result,work.error; }
fn resolveInner<H>(w: Work<H>&,context: u32,contract: Identity,input: const u32[:]) -> u32 {
 if w.error!=Error.none { return 0; } let self=w.store; let host=w.host; let point=mark(self); var success=false; defer { if !success { rollback(self,point); } }
 if self.active.len==0&&self.active_projections.len==0&&self.active_facts.len==0 { self.failure=blot_support::none<Code>(); self.trace=blot_eval_implementation_trace::Record {context:context,contract:contract}; }
 if !step(w) { return 0; } var arguments: u32[>..]=[]; arguments.append(input); for arg in arguments { if arg==0 { return fail(w,Error.unresolved_type); } }
 if !depthAvailable(self) { self.failure=blot_support::some(Code.associated_limit); return fail(w,Error.associated_limit); } let depth=self.active.len+self.active_projections.len+self.active_facts.len; if self.max_depth<depth+1 { self.max_depth=depth+1; }
 for active in self.active { if active.context==context&&active.contract==contract&&sameActiveArguments(self,active.arguments,arguments) { self.failure=blot_support::some(Code.recursive_evidence); return fail(w,Error.recursive_evidence); } }
 for arg in arguments { if !step(w) { return 0; } } let fingerprint=key(context,contract,arguments); let first=self.buckets.get(fingerprint); var known: u32=0; if first { known=first; }
 while known!=0 {
  if !step(w) { return 0; } let ordinal=known-1; let proof=self.proofs[ordinal];
  if proof.context==context&&proof.contract==contract&&sameArguments(self,proof.arguments,arguments) { let error=host.implementationRead(context,proof.implementation); if error!=Error.none { return fail(w,error); } self.trace.candidate(proof.implementation,Outcome.selected); self.hits++; success=true; return ordinal; } known=self.next[ordinal];
 }
 let saved=saveActive(self,arguments); self.active.push(Active {context,contract,saved}); defer { self.active.resize(self.active.len-1); self.active_arguments.resize(saved.start); }
 let owner_id=owner(host,context); if owner_id<0 { return fail(w,Error.type_mismatch); } let module=host.units[owner_id]; var winner=blot_support::none<blot_check_core::Implementation>(); var selected_mappings: Mapping[>..<]=[]; var selected_rows: RowMapping[>..<]=[]; var order: u32[>..]=[];
 for candidate,ordinal in module.implementations { if !step(w) { return 0; } if candidate.contract!=contract||candidate.head.len!=arguments.len { continue; } if candidate.private&&candidate.identity.unit!=context { continue; } order.push(ordinal as u32); }
 var exhausted=false;
 ::sort(order) { left,right =>
  if host.associated_remaining==0 { exhausted=true; return left<right; } host.associated_remaining--; return canonicalLess(host,module.implementations[left],module.implementations[right]);
 }
 if exhausted { self.failure=blot_support::some(Code.associated_limit); return fail(w,Error.associated_limit); }
 for ordinal in order {
  let candidate=module.implementations[ordinal]; if !step(w) { return 0; } self.candidates++; self.trace.candidate(candidate.identity,Outcome.head_mismatch);
  var mappings: Mapping[>..<]=[]; var rows: RowMapping[>..<]=[]; var matches=true;
  for pattern,index in module.types.list(candidate.head) { let matched,error=host.evidenceStore().matchWithRowsBudget(module.types,pattern,arguments[index],mappings,rows,host.associated_remaining); if error!=Error.none { return fail(w,error); } if !matched { matches=false; break; } }
  if !matches { continue; } self.trace.candidate(candidate.identity,Outcome.selected); if winner.present { return fail(w,Error.type_mismatch); } winner=blot_support::some(candidate); selected_mappings.append(mappings); selected_rows.append(rows);
 }
 if !winner.present { self.failure=blot_support::some(Code.missing_implementation); return fail(w,Error.missing_implementation); } let declaration=winner.value;
 let error=host.implementationRead(context,declaration.identity); if error!=Error.none { return fail(w,error); }
 let ms=self.provisional_mappings.len; let rs=self.provisional_rows.len; self.provisional_mappings.append(selected_mappings); self.provisional_rows.append(selected_rows); self.provisional_equations.push(Provisional {context,declaration,saved,List {ms as u32,selected_mappings.len as u32},List {rs as u32,selected_rows.len as u32}});
 defer { self.provisional_equations.resize(self.provisional_equations.len-1); self.provisional_mappings.resize(ms); self.provisional_rows.resize(rs); }
 var state=ProjectionContext<H> {host,self,context}; var resolver_=resolver(state); var edges: u32[>..]=[];
 for requirement in module.obligations[declaration.predicates.start..declaration.predicates.start+declaration.predicates.len] {
  if !step(w) { return 0; } self.prerequisite_edges++;
  if requirement.kind==K.contract {
   let product,err=host.evidenceStore().projectSelected(module.types,requirement.ty,selected_mappings,selected_rows,resolver_); if err!=Error.none { return fail(w,err); } if host.evidenceStore().node(product).tag!=Tag.product { return fail(w,Error.type_mismatch); }
   let traced,present=self.trace.step(product,0,Outcome.requires_evidence); let child=resolveInner(w,context,requirement.identity,host.evidenceStore().children(product)); if w.error!=Error.none { return 0; } edges.push(child); self.trace.setOutcome(traced,present,Outcome.selected);
  } else {
   let traced,present=self.trace.step(0,requirement.name,Outcome.requires_evidence); var observed: u32[4]=[0;4];
   let fact,exists,err=closedPredicateFrom(host,context,module,requirement,selected_mappings,selected_rows,resolver_,observed);
   if present { self.trace.steps[traced].ty=observed[0]; } var step_index: i64=-1; if present { step_index=traced; }
   if err!=Error.none { return rejectedPrerequisite(w,err,declaration.identity,step_index,requirement.kind); }
   if !exists { self.trace.candidate(declaration.identity,Outcome.requires_evidence); self.trace.setOutcome(traced,present,blot_eval_implementation_predicates::failureOutcome(requirement.kind)); self.failure=blot_support::some(Code.incompatible_implementation); return fail(w,Error.incompatible_implementation); }
   self.trace.setOutcome(traced,present,Outcome.selected); if present { self.trace.steps[traced].ty=fact.operands[0]; }
   let child=proveFact(w,context,fact,resolver_); if w.error!=Error.none { let err=w.error; w.error=Error.none; return rejectedPrerequisite(w,err,declaration.identity,step_index,requirement.kind); } edges.push(child);
  }
 }
 var members: Member[>..]=[];
 for member in module.implementation_members[declaration.members.start..declaration.members.start+declaration.members.len] {
  if !step(w) { return 0; } let root,err=host.evidenceStore().projectSelected(module.types,member.root,selected_mappings,selected_rows,resolver_); if err!=Error.none { return fail(w,err); }
  if member.kind==blot_check_core::ImplementationMemberKind.type_ { let error=unrestrictedAssociatedType(host,root,0); if error!=Error.none { return fail(w,error); } }
  self.trace.step(root,member.name,Outcome.selected); members.push(Member {member.name,member.kind,root,blot_check_core::BindingRef {member.target.unit,member.target.binding}});
 }
 let member_start=self.members.len; self.members.append(members); let edge_start=self.edges.len; self.edges.append(edges); let ordinal=self.proofs.len as u32; let bucket=self.buckets.get(fingerprint); var previous: u32=0; if bucket { previous=bucket; }
 self.next.push(previous); self.proofs.push(Proof {context:context,implementation:declaration.identity,contract:contract,arguments:saveArguments(self,arguments),members:List {member_start as u32,members.len as u32},prerequisites:List {edge_start as u32,edges.len as u32}}); self.buckets.insert(fingerprint,ordinal+1); success=true; return ordinal;
}
fn proveRequirement<H,R>(w: Work<H>&,context: u32,module: const blot_check_core::Module&,value: blot_check_core::Obligation,mappings: const Mapping[:],rows: const RowMapping[:],resolver_: blot_eval_type_evidence::ProjectionResolver<R>&) -> u32 {
 if !step(w) { return 0; } w.store.prerequisite_edges++;
 if value.kind==K.contract { let product,error=w.host.evidenceStore().projectSelected(module.types,value.ty,mappings,rows,resolver_); if error!=Error.none { return fail(w,error); } if w.host.evidenceStore().node(product).tag!=Tag.product { return fail(w,Error.type_mismatch); } return resolveInner(w,context,value.identity,w.host.evidenceStore().children(product)); }
 let fact,present,error=closedPredicateFrom(w.host,context,module,value,mappings,rows,resolver_,[]); if error!=Error.none { return fail(w,error); } if !present { w.store.failure=blot_support::some(Code.incompatible_implementation); return fail(w,Error.incompatible_implementation); } return proveFact(w,context,fact,resolver_);
}
fn proveFact<H,R>(w: Work<H>&,context: u32,value: Fact,resolver_: blot_eval_type_evidence::ProjectionResolver<R>&) -> u32 {
 if !step(w) { return 0; } let self=w.store; let host=w.host; let fact_key=FactKey {context,value}; let known=self.facts.get(fact_key); if known { self.hits++; return known; }
 if !depthAvailable(self) { self.failure=blot_support::some(Code.associated_limit); return fail(w,Error.associated_limit); }
 for active in self.active_facts { if !step(w) { return 0; } if active==fact_key { self.failure=blot_support::some(Code.recursive_evidence); return fail(w,Error.recursive_evidence); } }
 self.active_facts.push(fact_key); defer { self.active_facts.resize(self.active_facts.len-1); } var prerequisites: u32[>..]=[];
 if value.target.binding!=0 {
  let owner_id=owner(host,context); if owner_id<0 { return fail(w,Error.type_mismatch); } let module=host.units[owner_id]; var binding_id: u32=0; var found=false;
  for candidate,ordinal in module.bindings { if !step(w) { return 0; } if (value.target.unit==context&&value.target.binding==ordinal)||(candidate.kind==blot_check_check::Kind.external&&candidate.target==value.target) { binding_id=ordinal as u32; found=true; break; } }
  if !found { return fail(w,Error.type_mismatch); } let binding=module.bindings[binding_id]; var mappings: Mapping[>..<]=[]; var rows: RowMapping[>..<]=[]; var arity: i64=2;
  if value.kind==K.field||value.kind==K.writable_field||value.kind==K.result_dispatch { arity=1; }
  if value.kind==K.callee_use {
   let pack=host.evidenceStore().node(value.operands[0]); if pack.tag!=Tag.product||pack.b!=binding.public_variables.len+binding.public_rows.len { return fail(w,Error.type_mismatch); } let parts=host.evidenceStore().children(value.operands[0]);
   for variable,index in module.types.list(binding.public_variables) { if !step(w) { return 0; } mappings.push(Mapping {variable,parts[index]}); }
   for variable,index in module.types.list(binding.public_rows) { if !step(w) { return 0; } let carrier=host.evidenceStore().node(parts[binding.public_variables.len+index]); if carrier.tag!=Tag.function||carrier.a!=1||carrier.b!=1 { return fail(w,Error.type_mismatch); } rows.push(RowMapping {variable,carrier.c}); }
  } else if value.kind==K.resolver_dispatch { let matched,error=host.evidenceStore().matchLegacySignature(module.types,binding.scheme.root,value.operands[1],mappings,rows,resolver_); if error!=Error.none { return fail(w,error); } if !matched { return fail(w,Error.type_mismatch); } }
  else { let carrier,present,error=host.evidenceStore().matchPrerequisite(module.types,binding.scheme.root,value.operands,arity,mappings,rows,resolver_); if error!=Error.none { return fail(w,error); } if !present { return fail(w,Error.type_mismatch); } }
  let clauses=module.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start+binding.scheme.obligations.len]; var certificates: u32[>..]=[]; certificates.append(module.types.list(binding.scheme.closed_rows)); let body=module.body(binding_id); if body { certificates.append(module.types.list(body.closed_rows)); }
  let error=blot_eval_implementation_rows::reconstruct(host.evidenceStore(),module.types,clauses,certificates,module.types.list(binding.scheme.variables),mappings,rows,resolver_); if error!=Error.none { return fail(w,error); }
  for mapping in rows { var declared=false; for variable in module.types.list(binding.scheme.row_variables) { if !step(w) { return 0; } if variable==mapping.variable { declared=true; break; } } if !declared { return fail(w,Error.type_mismatch); } }
  for clause in clauses { let child=proveRequirement(w,context,module,clause,mappings,rows,resolver_); if w.error!=Error.none { return 0; } prerequisites.push(child); }
 }
 let start=self.edges.len; self.edges.append(prerequisites); let ordinal=self.proofs.len as u32; self.next.push(0); self.proofs.push(Proof {kind:ProofKind.predicate,predicate:value,context:context,implementation:Identity {0,0},contract:Identity {0,0},arguments:List {},members:List {},prerequisites:List {start as u32,prerequisites.len as u32}}); self.facts.insert(fact_key,ordinal); return ordinal;
}
enum FieldCheck { absent,matched,incompatible }
fn nominalFields<H,R>(host: H&,context: u32,module: const blot_check_core::Module&,value: blot_check_core::Obligation,operands: u32[4],resolver_: blot_eval_type_evidence::ProjectionResolver<R>&) -> FieldCheck,Error {
 let evidence=host.evidenceStore(); let input=evidence.node(operands[0]); let identity=Identity {input.a,input.b};
 for nominal in module.nominals {
  if nominal.identity!=identity { continue; } if nominal.is_opaque&&nominal.identity.unit!=context { return FieldCheck.absent,Error.none; } if nominal.constructors.len==0 { return FieldCheck.absent,Error.none; }
  var getter=false; if value.kind==K.field { for method in module.associated { if method.identity==identity&&method.member==value.name { getter=true; } } } var compatible=true;
  for constructor_index in module.extra[nominal.constructors.start..nominal.constructors.start+nominal.constructors.len] {
   if host.associated_remaining==0 { return FieldCheck.absent,Error.evidence_limit; } host.associated_remaining--; let constructor=module.constructors[constructor_index]; let signature=module.types.node(constructor.scheme.root); if signature.tag!=blot_check_types::Tag.function { return FieldCheck.absent,Error.none; }
   var mappings: Mapping[>..<]=[]; var rows: RowMapping[>..<]=[]; let matched,error=evidence.matchWithRowsBudget(module.types,signature.b,operands[0],mappings,rows,host.associated_remaining); if error!=Error.none { return FieldCheck.absent,error; } if !matched||constructor.payload==0 { return FieldCheck.absent,Error.none; }
   let payload,err=evidence.projectSelected(module.types,constructor.payload,mappings,rows,resolver_); if err!=Error.none { return FieldCheck.absent,err; } if evidence.node(payload).tag!=Tag.record { return FieldCheck.absent,Error.none; } var expected_payload=payload;
   if value.kind==K.update { var out_mappings: Mapping[>..<]=[]; var out_rows: RowMapping[>..<]=[]; let matched,error=evidence.matchWithRowsBudget(module.types,signature.b,operands[2],out_mappings,out_rows,host.associated_remaining); if error!=Error.none { return FieldCheck.absent,error; } if !matched { return FieldCheck.absent,Error.none; } let projected,e=evidence.projectSelected(module.types,constructor.payload,out_mappings,out_rows,resolver_); if e!=Error.none { return FieldCheck.absent,e; } expected_payload=projected; if evidence.node(projected).tag!=Tag.record { return FieldCheck.absent,Error.none; } }
   let fields=evidence.children(payload); let expected=evidence.children(expected_payload); if fields.len!=expected.len { return FieldCheck.absent,Error.none; } var found=false; var index=0;
   while index<fields.len { if host.associated_remaining==0 { return FieldCheck.absent,Error.evidence_limit; } host.associated_remaining--; if fields[index]!=expected[index] { return FieldCheck.absent,Error.none; }
    if fields[index]==value.name { found=true; if value.kind==K.update { if expected[index+1]!=operands[1] { compatible=false; } } else if fields[index+1]!=operands[2] { compatible=false; } }
    else if fields[index+1]!=expected[index+1] { compatible=false; } index+=2;
   }
   if !found { return FieldCheck.absent,Error.none; }
  }
  if !compatible||getter { return FieldCheck.incompatible,Error.none; } return FieldCheck.matched,Error.none;
 }
 return FieldCheck.absent,Error.none;
}
fn closedPredicate<H,R>(host: H&,context: u32,value: blot_check_core::Obligation,mappings: const Mapping[:],rows: const RowMapping[:],resolver_: blot_eval_type_evidence::ProjectionResolver<R>&) -> Fact,bool,Error { let index=owner(host,context); if index<0 { return Fact {},false,Error.type_mismatch; } return closedPredicateFrom(host,context,host.units[index],value,mappings,rows,resolver_,[]); }
fn closedPredicateFrom<H,R>(host: H&,context: u32,module: const blot_check_core::Module&,value: blot_check_core::Obligation,mappings: const Mapping[:],rows: const RowMapping[:],resolver_: blot_eval_type_evidence::ProjectionResolver<R>&,observed: u32[:]) -> Fact,bool,Error {
 let evidence=host.evidenceStore(); var operands: u32[4]=[0;4]; let roots: u32[4]=[value.ty,value.other,value.result,value.signature];
 if value.kind==K.effect_operation {
  let signature=module.types.node(value.signature); if signature.tag!=blot_check_types::Tag.function { return Fact {},false,Error.none; } let pack,error=evidence.projectSelected(module.types,value.other,mappings,rows,resolver_); if error!=Error.none { return Fact {},false,error; } if evidence.node(pack).tag!=Tag.product { return Fact {},false,Error.none; }
  let label,e=evidence.effects.internOperation(value.identity,evidence.children(pack)); if e!=Error.none { return Fact {},false,e; } let own_row,er=evidence.effects.internRow([label]); if er!=Error.none { return Fact {},false,er; }
  var inferred: RowMapping[>..<]=[]; inferred.append(rows); match module.types.row(signature.c).tail { variable v=>{ var known=false; for mapping in rows { if mapping.variable==v.value { known=true; break; } } if !known { inferred.push(RowMapping {v.value,own_row}); } },_=>{}, }
  for root,index in roots { if root!=0 { let projected,err=evidence.projectSelected(module.types,root,mappings,inferred,resolver_); if err!=Error.none { return Fact {},false,err; } operands[index]=projected; } if observed.len!=0 { for item,i in operands { observed[i]=item; } } }
  let closed=evidence.node(operands[3]); if closed.tag!=Tag.function { return Fact {},false,Error.none; }
  for known in evidence.effects.view().rowLabels(closed.c) { if host.associated_remaining==0 { return Fact {},false,Error.evidence_limit; } host.associated_remaining--; if known==label { return Fact {value.kind,value.operator,value.identity,value.name,operands,blot_check_core::BindingRef {0,0}},true,Error.none; } } return Fact {},false,Error.none;
 }
 for root,index in roots {
  if root!=0 { let projected,error=evidence.projectSelected(module.types,root,mappings,rows,resolver_);
   if error==Error.unresolved_type { let n=module.types.node(root); var variable=false; match module.types.row(n.c).tail { variable=>{ variable=true; },_=>{}, } if root!=value.signature||n.tag!=blot_check_types::Tag.function||n.a!=1||n.b!=1||module.types.rowLabels(n.c).len!=0||!variable { return Fact {},false,error; } operands[index]=0; continue; }
   if error!=Error.none { return Fact {},false,error; } operands[index]=projected;
  } if observed.len!=0 { for item,i in operands { observed[i]=item; } }
 }
 var target=blot_check_core::BindingRef {0,0}; var accepted=false;
 if value.kind==K.resolver_shape {
  let resolver=evidence.node(operands[0]); let result=evidence.node(operands[2]); if resolver.tag==Tag.resolver&&result.tag==Tag.nominal { let token=evidence.node(resolver.a); if token.tag==Tag.type_constructor&&token.a==result.a&&token.b==result.b { for nominal in module.nominals { if host.associated_remaining==0 { return Fact {},false,Error.evidence_limit; } host.associated_remaining--; if nominal.identity.unit==token.a&&nominal.identity.decl==token.b { accepted=nominal.parameters.len==evidence.children(operands[2]).len; } } } }
 } else if value.kind==K.monad_factory { accepted=evidence.node(operands[0]).tag==Tag.type_constructor; }
 else if value.kind==K.effect_handler {
  let token=evidence.node(operands[0]); let extended=evidence.node(operands[3]); let residual=evidence.node(operands[1]);
  if token.tag==Tag.nominal&&extended.tag==Tag.function&&residual.tag==Tag.function { let label,error=evidence.effects.internOperation(Identity {token.a,token.b},evidence.children(operands[0])); if error!=Error.none { return Fact {},false,error; } var labels: u32[>..<]=[label]; for known in evidence.effects.view().rowLabels(residual.c) { if host.associated_remaining==0 { return Fact {},false,Error.evidence_limit; } host.associated_remaining--; labels.push(known); } let row,err=evidence.effects.internRow(labels); if err!=Error.none { return Fact {},false,err; } accepted=row==extended.c; }
 } else if value.kind==K.collection { let collection=evidence.node(operands[0]); accepted=(collection.tag==Tag.array||collection.tag==Tag.list)&&collection.a==operands[2]; }
 else if value.kind==K.type_head { var head=operands[0]; var depth=0; while evidence.node(head).tag==Tag.function { if depth>=256||host.associated_remaining==0 { return Fact {},false,Error.evidence_limit; } host.associated_remaining--; head=evidence.node(head).b; depth++; } accepted=head==operands[2]; }
 else if value.kind==K.record_merge {
  if evidence.node(operands[0]).tag==Tag.never||evidence.node(operands[1]).tag==Tag.never { accepted=evidence.node(operands[2]).tag==Tag.never; }
  else if evidence.node(operands[0]).tag==Tag.record&&evidence.node(operands[1]).tag==Tag.record {
   var fields: u32[>..<]=[]; let left=evidence.children(operands[0]); let right=evidence.children(operands[1]); var first=0; var second=0;
   while first<left.len||second<right.len { if host.associated_remaining==0 { return Fact {},false,Error.evidence_limit; } host.associated_remaining--; if second==right.len||(first<left.len&&left[first]<right[second]) { fields.append(left[first..first+2]); first+=2; } else { if first<left.len&&left[first]==right[second] { first+=2; } fields.append(right[second..second+2]); second+=2; } }
   let merged,error=evidence.intern(Tag.record,0,0,fields); if error!=Error.none { return Fact {},false,error; } accepted=operands[2]==merged;
  }
 } else if value.kind==K.update {
  if evidence.node(operands[0]).tag==Tag.record { var fields: u32[>..<]=[]; fields.append(evidence.children(operands[0])); var found=false; var index=0;
   while index<fields.len { if host.associated_remaining==0 { return Fact {},false,Error.evidence_limit; } host.associated_remaining--; if fields[index]==value.name { fields[index+1]=operands[1]; found=true; } index+=2; }
   if found { let updated,error=evidence.intern(Tag.record,0,0,fields); if error!=Error.none { return Fact {},false,error; } accepted=operands[2]==updated; }
   if operands[3]==0 { let carrier,error=evidence.intern(Tag.function,1,1,[]); if error!=Error.none { return Fact {},false,error; } operands[3]=carrier; }
  } else if evidence.node(operands[0]).tag==Tag.nominal { let state,error=nominalFields(host,context,module,value,operands,resolver_); if error!=Error.none { return Fact {},false,error; } accepted=state==FieldCheck.matched; if operands[3]==0 { let carrier,error=evidence.intern(Tag.function,1,1,[]); if error!=Error.none { return Fact {},false,error; } operands[3]=carrier; } }
 } else if value.kind==K.field||value.kind==K.writable_field {
  var structural=FieldCheck.absent; if evidence.node(operands[0]).tag==Tag.nominal { let check,error=nominalFields(host,context,module,value,operands,resolver_); if error!=Error.none { return Fact {},false,error; } structural=check; } if structural==FieldCheck.incompatible { return Fact {},false,Error.none; }
  if structural==FieldCheck.matched { accepted=true; } else { let selected,present,error=host.implementationLegacyPredicate(context,value,operands,resolver_); if error!=Error.none { return Fact {},false,error; } if !present { return Fact {},false,Error.none; } target=selected.target; operands[3]=selected.carrier; accepted=true; }
 } else if value.kind==K.callee_use {
  for candidate,ordinal in module.bindings { if ((value.identity.unit==module.unit||value.identity.unit==0)&&value.identity.decl==ordinal)||(candidate.kind==blot_check_check::Kind.external&&candidate.target.unit==value.identity.unit&&candidate.target.binding==value.identity.decl) { target=candidate.target; if target.unit==0 { target.unit=module.unit; } accepted=target.binding!=0; break; } }
 } else if value.kind==K.type_eq { accepted=operands[0]==operands[2]; }
 else if value.kind==K.type_rep||value.kind==K.effect_rep { accepted=true; }
 else if value.kind==K.arithmetic||value.kind==K.ordered { let tag=evidence.node(operands[0]).tag; accepted=tag==Tag.unsigned32||tag==Tag.floating32; }
 else if value.kind==K.integer { accepted=evidence.node(operands[0]).tag==Tag.unsigned32; }
 else if value.kind==K.equality { let tag=evidence.node(operands[0]).tag; accepted=tag==Tag.unsigned32||tag==Tag.floating32||tag==Tag.boolean; }
 else { let selected,present,error=host.implementationLegacyPredicate(context,value,operands,resolver_); if error!=Error.none { return Fact {},false,error; } if !present { return Fact {},false,Error.none; } target=selected.target; operands[3]=selected.carrier; accepted=true; }
 if !accepted { return Fact {},false,Error.none; } return Fact {value.kind,value.operator,value.identity,value.name,operands,target},true,Error.none;
}
fn invocation<H>(host: H&,value: blot_check_core::Obligation,operands: u32[4]) -> u32,Error {
 var row: u32=0; if operands[3]!=0 { let carrier=host.evidenceStore().node(operands[3]); if carrier.tag!=Tag.function { return 0,Error.type_mismatch; } row=carrier.c; }
 if value.kind==K.field||value.kind==K.writable_field { return host.evidenceStore().internWithEffects(Tag.function,operands[0],operands[2],row,[]); }
 let result,error=host.evidenceStore().internWithEffects(Tag.function,operands[1],operands[2],row,[]); if error!=Error.none { return 0,error; } return host.evidenceStore().internWithEffects(Tag.function,operands[0],result,row,[]);
}
fn predicate<H,R>(host: H&,context: u32,value: blot_check_core::Obligation,mappings: const Mapping[:],rows: const RowMapping[:],resolver_: blot_eval_type_evidence::ProjectionResolver<R>&) -> bool,Error { let fact,present,error=closedPredicate(host,context,value,mappings,rows,resolver_); return present,error; }
