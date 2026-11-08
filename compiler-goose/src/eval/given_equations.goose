namespace blot_eval_given_equations;
import check.types;
import support.error;
import support.pooled_buffer;

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
recursive fn ty(self_:Rewrite&,root:u32,memo:Memo&,depth:i64)->u32 {var equations=Equations{};var equivalent=Words{};let result=tyValue(self_,root,memo,depth,equations,equivalent);equivalent.deinit();equations.deinit();return result;}
recursive fn tyValue(self_: Rewrite&,root: u32,memo: Memo&,depth: i64,equations:Equations&,equivalent:Words&) -> u32 {
 if self_.failure!=blot_error::Error.none { return 0; } { let known=memo.types.get(root); if known { return known; } } if depth>=256 { self_.failure=blot_error::Error.type_limit; return 0; } if !charge(self_) { return 0; }
 let original=resolve(self_,root); if self_.failure!=blot_error::Error.none { return 0; } memo.types.insert(root,original);
 for equation in self_.equations { if !charge(self_) { return 0; } let left=node(self_,resolve(self_,equation.left),memo,depth+1); let right=node(self_,resolve(self_,equation.right),memo,depth+1); equations.push(Equation {left,right}); if scratchFailed(self_,equations.failure) {return 0;} }
 equivalent.push(original); if scratchFailed(self_,equivalent.failure) {return 0;} var index=0; var id=original;
 while index<equivalent.len&&self_.failure==blot_error::Error.none {
  let item=equivalent.items[index];
  for equation in equations.items {
   if !charge(self_) { return 0; } var next: u32=0;
   if equal(self_,item,equation.left) { next=equation.right; } else if equal(self_,item,equation.right) { next=equation.left; } else { continue; }
   var seen=false; for known in equivalent.items { if equal(self_,known,next) { seen=true; } } if self_.failure!=blot_error::Error.none { return 0; } if seen { continue; }
   equivalent.push(next); if scratchFailed(self_,equivalent.failure) {return 0;} if rank(self_,next)<rank(self_,id)||(rank(self_,next)==rank(self_,id)&&next<id) { id=next; }
  }
  index++;
 }
 if self_.failure!=blot_error::Error.none { return 0; } memo.types.insert(root,id); var result=node(self_,id,memo,depth); if result!=id { result=ty(self_,result,memo,depth+1); } if self_.failure!=blot_error::Error.none { return 0; } memo.types.insert(root,result); return result;
}
recursive fn node(self_:Rewrite&,id:u32,memo:Memo&,depth:i64)->u32 {var old=Words{};var parts=Words{};var fields=Fields{};let result=nodeValue(self_,id,memo,depth,old,parts,fields);fields.deinit();parts.deinit();old.deinit();return result;}
recursive fn nodeValue(self_: Rewrite&,id: u32,memo: Memo&,depth: i64,old:Words&,parts:Words&,fields:Fields&) -> u32 {
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
  if tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection { old.append(self_.store.nominalArguments(n)); } else { old.append(self_.store.list(blot_check_types::List {n.a,n.b})); } if scratchFailed(self_,old.failure) {return 0;}
  var changed=false; for child in old.items { let next=ty(self_,child,memo,depth+1); changed=changed||next!=child; parts.push(next); if scratchFailed(self_,parts.failure) {return 0;} } if self_.failure!=blot_error::Error.none { return 0; } if !changed { return id; }
  if tag==blot_check_types::Tag.projection { let value,error=self_.store.projection(blot_check_types::NominalIdentity {n.a,n.b},self_.store.projectionMember(n),parts.items); return take(self_,value,error); }
  if tag==blot_check_types::Tag.nominal { let value,error=self_.store.nominal(blot_check_types::NominalIdentity {n.a,n.b},parts.items); return take(self_,value,error); } let value,error=self_.store.product(parts.items); return take(self_,value,error);
 }
 if tag==blot_check_types::Tag.record { var changed=false; for at in 0..n.b { let field=self_.store.recordField(n,at); let next=ty(self_,field.ty,memo,depth+1); changed=changed||next!=field.ty; fields.push(blot_check_types::Field {field.name,next}); if scratchFailed(self_,fields.failure) {return 0;} } if self_.failure!=blot_error::Error.none { return 0; } if !changed { return id; } let value,error=self_.store.record(fields.items); return take(self_,value,error); }
 if tag==blot_check_types::Tag.state_provider { let a=ty(self_,n.a,memo,depth+1); let b=ty(self_,n.b,memo,depth+1); let c=ty(self_,n.c,memo,depth+1); if self_.failure!=blot_error::Error.none { return 0; } if a==n.a&&b==n.b&&c==n.c { return id; } let value,error=self_.store.stateProvider(a,b,c); return take(self_,value,error); }
 return id;
}
recursive fn effectRow(self_:Rewrite&,root:u32,memo:Memo&,depth:i64)->u32 {var labels=Words{};let result=effectRowValue(self_,root,memo,depth,labels);labels.deinit();return result;}
recursive fn effectRowValue(self_: Rewrite&,root: u32,memo: Memo&,depth: i64,labels:Words&) -> u32 {
 if self_.failure!=blot_error::Error.none { return 0; } { let known=memo.rows.get(root); if known { return known; } } if depth>=256 { self_.failure=blot_error::Error.type_limit; return 0; }
 let id,error=self_.store.resolveEffects(root,0); if error!=blot_error::Error.none { return take(self_,0,error); } let row=self_.store.row(id); labels.append(self_.store.rowLabels(id)); if scratchFailed(self_,labels.failure) {return 0;} var changed=false;
 for index in 0..labels.len {
  if !charge(self_) { return 0; } effectOperation(self_,labels,index,changed,memo,depth); if self_.failure!=blot_error::Error.none {return 0;}
 }
 var result=id; if changed { let value,err=self_.store.effects.rowAt(labels.items,row.tail,row.cursor); if err!=blot_error::Error.none { return take(self_,0,blot_check_types::effectError(err)); } result=value; } memo.rows.insert(root,result); return result;
}
recursive fn effectOperation(self_:Rewrite&,labels:Words&,index:i64,changed:bool&,memo:Memo&,depth:i64)->u32 {var arguments=Words{};let result=effectOperationValue(self_,labels,index,changed,memo,depth,arguments);arguments.deinit();return result;}
recursive fn effectOperationValue(self_:Rewrite&,labels:Words&,index:i64,changed:bool&,memo:Memo&,depth:i64,arguments:Words&)->u32 {
 let operation=self_.store.operation(labels.items[index]); arguments.append(self_.store.operationArguments(labels.items[index])); if scratchFailed(self_,arguments.failure) {return 0;}
  for i in 0..arguments.len { arguments.items[i]=ty(self_,arguments.items[i],memo,depth+1); } var instance=operation.instance; if instance.unit==0&&instance.decl!=0 { instance.decl=ty(self_,instance.decl,memo,depth+1); } if self_.failure!=blot_error::Error.none { return 0; }
  let next,err=self_.store.internScopedOperation(operation.identity,instance,arguments.items); if err!=blot_error::Error.none { return take(self_,0,err); } changed=changed||next!=labels.items[index]; labels.items[index]=next;
 return 0;
}

fn normalize(self_: Rewrite&,root: u32) -> u32,Error { if self_.equations.len==0 { return self_.store.resolve(root,0); } self_.failure=blot_error::Error.none; var types: dictionary<u32,u32> = dictionary<u32,u32>{}; var rows: dictionary<u32,u32> = dictionary<u32,u32>{}; var memo=Memo {types,rows}; let result=ty(self_,root,memo,0); return result,self_.failure; }

fn scratchFailed(self_:Rewrite&,error:Error)->bool {if error==blot_error::Error.none {return false;}if self_.failure==blot_error::Error.none {self_.failure=error;}return true;}
struct Words {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var scratch_Words:u32[>..]=[];
fn push(self_:Words&,value:u32) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,scratch_Words);self_.len=self_.items.len;}
fn append(self_:Words&,values:const u32[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,scratch_Words);self_.len=self_.items.len;}
fn deinit(self_:Words&) {blot_support_pooled_buffer::deinit(self_,scratch_Words);self_.len=0;self_.failure=blot_error::Error.none;}
struct Fields {storage:blot_check_types::Field[:]=default<blot_check_types::Field[:]>(),items:blot_check_types::Field[:]=default<blot_check_types::Field[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var scratch_Fields:blot_check_types::Field[>..]=[];
fn push(self_:Fields&,value:blot_check_types::Field) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,scratch_Fields);self_.len=self_.items.len;}
fn append(self_:Fields&,values:const blot_check_types::Field[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,scratch_Fields);self_.len=self_.items.len;}
fn deinit(self_:Fields&) {blot_support_pooled_buffer::deinit(self_,scratch_Fields);self_.len=0;self_.failure=blot_error::Error.none;}
struct Equations {storage:Equation[:]=default<Equation[:]>(),items:Equation[:]=default<Equation[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var scratch_Equations:Equation[>..]=[];
fn push(self_:Equations&,value:Equation) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,scratch_Equations);self_.len=self_.items.len;}
fn append(self_:Equations&,values:const Equation[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,scratch_Equations);self_.len=self_.items.len;}
fn deinit(self_:Equations&) {blot_support_pooled_buffer::deinit(self_,scratch_Equations);self_.len=0;self_.failure=blot_error::Error.none;}
