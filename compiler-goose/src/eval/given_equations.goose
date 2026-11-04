namespace blot_eval_given_equations;
import dictionary;
import check.types;
import support.error;
type Error=blot_error::Error;
struct Equation { left: u32,right: u32 }
struct Memo { types: dictionary<u32,u32>&,rows: dictionary<u32,u32>& }
struct Rewrite { store: blot_check_types::Store&,equations: const Equation[:],failure: Error=Error.none }
fn take(self: Rewrite&,id: u32,error: Error) -> u32 { if self.failure==Error.none { self.failure=error; } return id; }
fn charge(self: Rewrite&) -> bool { if self.failure!=Error.none { return false; } self.failure=self.store.chargeProjection(); return self.failure==Error.none; }
fn resolve(self: Rewrite&,id: u32) -> u32 { if self.failure!=Error.none { return 0; } let value,error=self.store.resolve(id,0); return take(self,value,error); }
fn equal(self: Rewrite&,a: u32,b: u32) -> bool { if self.failure!=Error.none { return false; } let result,error=self.store.equalSymbolic(a,b); if error!=Error.none { self.failure=error; } return result; }
fn rank(self: Rewrite&,id: u32) -> u8 { let tag=self.store.node(id).tag; if tag==blot_check_types::Tag.projection { return 2; } if tag==blot_check_types::Tag.variable { return 1; } return 0; }
fn ty(self: Rewrite&,root: u32,memo: Memo&,depth: i64) -> u32 {
 if self.failure!=Error.none { return 0; } let known=memo.types.get(root); if known { return known; } if depth>=256 { self.failure=Error.type_limit; return 0; } if !charge(self) { return 0; }
 let original=resolve(self,root); if self.failure!=Error.none { return 0; } memo.types.insert(root,original); var equations: Equation[>..]=[];
 for equation in self.equations { if !charge(self) { return 0; } let left=node(self,resolve(self,equation.left),memo,depth+1); let right=node(self,resolve(self,equation.right),memo,depth+1); equations.push(Equation {left,right}); }
 var equivalent: u32[>..]=[original]; var index=0; var id=original;
 while index<equivalent.len&&self.failure==Error.none {
  let item=equivalent[index];
  for equation in equations {
   if !charge(self) { return 0; } var next: u32=0;
   if equal(self,item,equation.left) { next=equation.right; } else if equal(self,item,equation.right) { next=equation.left; } else { continue; }
   var seen=false; for known in equivalent { if equal(self,known,next) { seen=true; } } if self.failure!=Error.none { return 0; } if seen { continue; }
   equivalent.push(next); if rank(self,next)<rank(self,id)||(rank(self,next)==rank(self,id)&&next<id) { id=next; }
  }
  index++;
 }
 if self.failure!=Error.none { return 0; } memo.types.insert(root,id); var result=node(self,id,memo,depth); if result!=id { result=ty(self,result,memo,depth+1); } if self.failure!=Error.none { return 0; } memo.types.insert(root,result); return result;
}
fn node(self: Rewrite&,id: u32,memo: Memo&,depth: i64) -> u32 {
 if self.failure!=Error.none { return 0; } let n=self.store.node(id); let tag=n.tag;
 if tag==blot_check_types::Tag.scoped {
  let descriptor=ty(self,n.a,memo,depth+1); var identity=n.c; if n.b==0 { identity=ty(self,n.c,memo,depth+1); } if self.failure!=Error.none { return 0; } if descriptor==n.a&&identity==n.c { return id; }
  let value,error=self.store.scoped(descriptor,blot_check_types::NominalIdentity {n.b,identity}); return take(self,value,error);
 }
 if tag==blot_check_types::Tag.function {
  let a=ty(self,n.a,memo,depth+1); let b=ty(self,n.b,memo,depth+1); let row=effectRow(self,n.c,memo,depth+1); if self.failure!=Error.none { return 0; } if a==n.a&&b==n.b&&row==n.c { return id; }
  let value,error=self.store.functionWithEffects(a,b,row); return take(self,value,error);
 }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider {
  let a=ty(self,n.a,memo,depth+1); var row=n.c; if tag==blot_check_types::Tag.provider { row=effectRow(self,n.c,memo,depth+1); } if self.failure!=Error.none { return 0; } if a==n.a&&row==n.c { return id; }
  if tag==blot_check_types::Tag.resolver { let value,error=self.store.resolver(a); return take(self,value,error); } if tag==blot_check_types::Tag.provider { let value,error=self.store.provider(a,row); return take(self,value,error); } let value,error=self.store.sequence(tag,a); return take(self,value,error);
 }
 if tag==blot_check_types::Tag.product||tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection {
  var old: u32[>..]=[]; if tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection { old.append(self.store.nominalArguments(n)); } else { old.append(self.store.list(blot_check_types::List {n.a,n.b})); }
  var parts: u32[>..]=[]; var changed=false; for child in old { let next=ty(self,child,memo,depth+1); changed=changed||next!=child; parts.push(next); } if self.failure!=Error.none { return 0; } if !changed { return id; }
  if tag==blot_check_types::Tag.projection { let value,error=self.store.projection(blot_check_types::NominalIdentity {n.a,n.b},self.store.projectionMember(n),parts); return take(self,value,error); }
  if tag==blot_check_types::Tag.nominal { let value,error=self.store.nominal(blot_check_types::NominalIdentity {n.a,n.b},parts); return take(self,value,error); } let value,error=self.store.product(parts); return take(self,value,error);
 }
 if tag==blot_check_types::Tag.record { var parts: blot_check_types::Field[>..]=[]; var changed=false; for at in 0..n.b { let field=self.store.recordField(n,at); let next=ty(self,field.ty,memo,depth+1); changed=changed||next!=field.ty; parts.push(blot_check_types::Field {field.name,next}); } if self.failure!=Error.none { return 0; } if !changed { return id; } let value,error=self.store.record(parts); return take(self,value,error); }
 if tag==blot_check_types::Tag.state_provider { let a=ty(self,n.a,memo,depth+1); let b=ty(self,n.b,memo,depth+1); let c=ty(self,n.c,memo,depth+1); if self.failure!=Error.none { return 0; } if a==n.a&&b==n.b&&c==n.c { return id; } let value,error=self.store.stateProvider(a,b,c); return take(self,value,error); }
 return id;
}
fn effectRow(self: Rewrite&,root: u32,memo: Memo&,depth: i64) -> u32 {
 if self.failure!=Error.none { return 0; } let known=memo.rows.get(root); if known { return known; } if depth>=256 { self.failure=Error.type_limit; return 0; }
 let id,error=self.store.resolveEffects(root,0); if error!=Error.none { return take(self,0,error); } let row=self.store.row(id); var labels: u32[>..]=[]; labels.append(self.store.rowLabels(id)); var changed=false;
 for index in 0..labels.len {
  if !charge(self) { return 0; } let operation=self.store.operation(labels[index]); var arguments: u32[>..]=[]; arguments.append(self.store.operationArguments(labels[index]));
  for i in 0..arguments.len { arguments[i]=ty(self,arguments[i],memo,depth+1); } var instance=operation.instance; if instance.unit==0&&instance.decl!=0 { instance.decl=ty(self,instance.decl,memo,depth+1); } if self.failure!=Error.none { return 0; }
  let next,err=self.store.internScopedOperation(operation.identity,instance,arguments); if err!=Error.none { return take(self,0,err); } changed=changed||next!=labels[index]; labels[index]=next;
 }
 var result=id; if changed { let value,err=self.store.effects.rowAt(labels,row.tail,row.cursor); if err!=Error.none { return take(self,0,blot_check_types::effectError(err)); } result=value; } memo.rows.insert(root,result); return result;
}
fn normalize(self: Rewrite&,root: u32) -> u32,Error { if self.equations.len==0 { return self.store.resolve(root,0); } self.failure=Error.none; var types: dictionary<u32,u32>; var rows: dictionary<u32,u32>; var memo=Memo {types,rows}; let result=ty(self,root,memo,0); return result,self.failure; }
