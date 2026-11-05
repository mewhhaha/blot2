namespace blot_eval_given_equations;
import check.types;
import support.error;

import dictionary;
type Error=blot_error::Error;
struct Equation { left: u32,right: u32 }
struct Memo { types: dictionary<u32,u32>&,rows: dictionary<u32,u32>& }
struct Rewrite { store: blot_check_types::Store&,equations: const Equation[:],failure: Error=blot_error::Error.none }
fn take(self_: Rewrite&,id: u32,error: Error) -> u32 { if self_.failure==blot_error::Error.none { self_.failure=error; } return id; }
fn charge(self_: Rewrite&) -> bool { if self_.failure!=blot_error::Error.none { return false; } self_.failure=self_.store.chargeProjection(); return self_.failure==blot_error::Error.none; }
fn resolve(self_: Rewrite&,id: u32) -> u32 { if self_.failure!=blot_error::Error.none { return 0; } let value,error=self_.store.resolve(id,0); return take(self_,value,error); }
fn equal(self_: Rewrite&,a: u32,b: u32) -> bool { if self_.failure!=blot_error::Error.none { return false; } let result,error=self_.store.equalSymbolic(a,b); if error!=blot_error::Error.none { self_.failure=error; } return result; }
fn rank(self_: Rewrite&,id: u32) -> u8 { let tag=self_.store.node(id).tag; if tag==blot_check_types::Tag.projection { return 2; } if tag==blot_check_types::Tag.variable { return 1; } return 0; }
fn ty(self_: Rewrite&,root: u32,memo: Memo&,depth: i64) -> u32 {
 if self_.failure!=blot_error::Error.none { return 0; } let known=memo.types.get(root); if known { return known; } if depth>=256 { self_.failure=blot_error::Error.type_limit; return 0; } if !charge(self_) { return 0; }
 let original=resolve(self_,root); if self_.failure!=blot_error::Error.none { return 0; } memo.types.insert(root,original); var equations: Equation[>..]=[];
 for equation in self_.equations { if !charge(self_) { return 0; } let left=node(self_,resolve(self_,equation.left),memo,depth+1); let right=node(self_,resolve(self_,equation.right),memo,depth+1); equations.push(Equation {left,right}); }
 var equivalent: u32[>..]=[original]; var index=0; var id=original;
 while index<equivalent.len&&self_.failure==blot_error::Error.none {
  let item=equivalent[index];
  for equation in equations {
   if !charge(self_) { return 0; } var next: u32=0;
   if equal(self_,item,equation.left) { next=equation.right; } else if equal(self_,item,equation.right) { next=equation.left; } else { continue; }
   var seen=false; for known in equivalent { if equal(self_,known,next) { seen=true; } } if self_.failure!=blot_error::Error.none { return 0; } if seen { continue; }
   equivalent.push(next); if rank(self_,next)<rank(self_,id)||(rank(self_,next)==rank(self_,id)&&next<id) { id=next; }
  }
  index++;
 }
 if self_.failure!=blot_error::Error.none { return 0; } memo.types.insert(root,id); var result=node(self_,id,memo,depth); if result!=id { result=ty(self_,result,memo,depth+1); } if self_.failure!=blot_error::Error.none { return 0; } memo.types.insert(root,result); return result;
}
fn node(self_: Rewrite&,id: u32,memo: Memo&,depth: i64) -> u32 {
 if self_.failure!=blot_error::Error.none { return 0; } let n=self_.store.node(id); let tag=n.tag;
 if tag==blot_check_types::Tag.scoped {
  let descriptor=ty(self_,n.a,memo,depth+1); var identity=n.c; if n.b==0 { identity=ty(self_,n.c,memo,depth+1); } if self_.failure!=blot_error::Error.none { return 0; } if descriptor==n.a&&identity==n.c { return id; }
  let value,error=self_.store.scoped(descriptor,blot_check_types::NominalIdentity {n.b,identity}); return take(self_,value,error);
 }
 if tag==blot_check_types::Tag.function {
  let a=ty(self_,n.a,memo,depth+1); let b=ty(self_,n.b,memo,depth+1); let row=effectRow(self_,n.c,memo,depth+1); if self_.failure!=blot_error::Error.none { return 0; } if a==n.a&&b==n.b&&row==n.c { return id; }
  let value,error=self_.store.functionWithEffects(a,b,row); return take(self_,value,error);
 }
 if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider {
  let a=ty(self_,n.a,memo,depth+1); var row=n.c; if tag==blot_check_types::Tag.provider { row=effectRow(self_,n.c,memo,depth+1); } if self_.failure!=blot_error::Error.none { return 0; } if a==n.a&&row==n.c { return id; }
  if tag==blot_check_types::Tag.resolver { let value,error=self_.store.resolver(a); return take(self_,value,error); } if tag==blot_check_types::Tag.provider { let value,error=self_.store.provider(a,row); return take(self_,value,error); } let value,error=self_.store.sequence(tag,a); return take(self_,value,error);
 }
 if tag==blot_check_types::Tag.product||tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection {
  var old: u32[>..]=[]; if tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection { old.append(self_.store.nominalArguments(n)); } else { old.append(self_.store.list(blot_check_types::List {n.a,n.b})); }
  var parts: u32[>..]=[]; var changed=false; for child in old { let next=ty(self_,child,memo,depth+1); changed=changed||next!=child; parts.push(next); } if self_.failure!=blot_error::Error.none { return 0; } if !changed { return id; }
  if tag==blot_check_types::Tag.projection { let value,error=self_.store.projection(blot_check_types::NominalIdentity {n.a,n.b},self_.store.projectionMember(n),parts); return take(self_,value,error); }
  if tag==blot_check_types::Tag.nominal { let value,error=self_.store.nominal(blot_check_types::NominalIdentity {n.a,n.b},parts); return take(self_,value,error); } let value,error=self_.store.product(parts); return take(self_,value,error);
 }
 if tag==blot_check_types::Tag.record { var parts: blot_check_types::Field[>..]=[]; var changed=false; for at in 0..n.b { let field=self_.store.recordField(n,at); let next=ty(self_,field.ty,memo,depth+1); changed=changed||next!=field.ty; parts.push(blot_check_types::Field {field.name,next}); } if self_.failure!=blot_error::Error.none { return 0; } if !changed { return id; } let value,error=self_.store.record(parts); return take(self_,value,error); }
 if tag==blot_check_types::Tag.state_provider { let a=ty(self_,n.a,memo,depth+1); let b=ty(self_,n.b,memo,depth+1); let c=ty(self_,n.c,memo,depth+1); if self_.failure!=blot_error::Error.none { return 0; } if a==n.a&&b==n.b&&c==n.c { return id; } let value,error=self_.store.stateProvider(a,b,c); return take(self_,value,error); }
 return id;
}
fn effectRow(self_: Rewrite&,root: u32,memo: Memo&,depth: i64) -> u32 {
 if self_.failure!=blot_error::Error.none { return 0; } let known=memo.rows.get(root); if known { return known; } if depth>=256 { self_.failure=blot_error::Error.type_limit; return 0; }
 let id,error=self_.store.resolveEffects(root,0); if error!=blot_error::Error.none { return take(self_,0,error); } let row=self_.store.row(id); var labels: u32[>..]=[]; labels.append(self_.store.rowLabels(id)); var changed=false;
 for index in 0..labels.len {
  if !charge(self_) { return 0; } let operation=self_.store.operation(labels[index]); var arguments: u32[>..]=[]; arguments.append(self_.store.operationArguments(labels[index]));
  for i in 0..arguments.len { arguments[i]=ty(self_,arguments[i],memo,depth+1); } var instance=operation.instance; if instance.unit==0&&instance.decl!=0 { instance.decl=ty(self_,instance.decl,memo,depth+1); } if self_.failure!=blot_error::Error.none { return 0; }
  let next,err=self_.store.internScopedOperation(operation.identity,instance,arguments); if err!=blot_error::Error.none { return take(self_,0,err); } changed=changed||next!=labels[index]; labels[index]=next;
 }
 var result=id; if changed { let value,err=self_.store.effects.rowAt(labels,row.tail,row.cursor); if err!=blot_error::Error.none { return take(self_,0,blot_check_types::effectError(err)); } result=value; } memo.rows.insert(root,result); return result;
}
fn normalize(self_: Rewrite&,root: u32) -> u32,Error { if self_.equations.len==0 { return self_.store.resolve(root,0); } self_.failure=blot_error::Error.none; var types: dictionary<u32,u32>; var rows: dictionary<u32,u32>; var memo=Memo {types,rows}; let result=ty(self_,root,memo,0); return result,self_.failure; }
