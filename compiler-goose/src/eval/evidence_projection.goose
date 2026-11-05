namespace blot_eval_evidence_projection;
import check.types;
import eval.type_evidence;
import support.error;

type View=blot_eval_type_evidence::View;
type Tag=blot_eval_type_evidence::Tag;
type Error=blot_error::Error;
struct Comparison { view: View,shift: u32,remaining: i64& }
fn step(self_: Comparison&,depth: i64) -> Error { if depth>=128||self_.remaining==0 { return blot_error::Error.evidence_limit; } self_.remaining--; return blot_error::Error.none; }
fn equal(self_: Comparison&,left: u32,right: u32,local: i64,depth: i64) -> bool,Error {
 let err=step(self_,depth); if err!=blot_error::Error.none { return false,err; }
 if left==0||right==0||left>=self_.view.nodes.len||right>=self_.view.nodes.len { return false,blot_error::Error.type_mismatch; }
 let a=self_.view.node(left); let b=self_.view.node(right); if a.tag!=b.tag { return false,blot_error::Error.none; }
 if a.tag==blot_eval_type_evidence::Tag.bound { var expected=a.c; if expected>=local { if expected>0xffffffff-self_.shift { return false,blot_error::Error.evidence_limit; } expected+=self_.shift; } return a.a==b.a&&a.b==b.b&&expected==b.c,blot_error::Error.none; }
 if a.tag==blot_eval_type_evidence::Tag.forall||a.tag==blot_eval_type_evidence::Tag.existential {
  if a.b!=b.b { return false,blot_error::Error.none; }
  let xs=self_.view.children(left); let ys=self_.view.children(right);
  for x,index in xs { let first=self_.view.node(x); let second=self_.view.node(ys[index]); if first.tag!=blot_eval_type_evidence::Tag.bound||second.tag!=blot_eval_type_evidence::Tag.bound||first.a!=second.a||first.b!=second.b||first.c!=0||second.c!=0 { return false,blot_error::Error.none; } }
  let goals=self_.view.quantifierGoals(left); let others=self_.view.quantifierGoals(right); if goals.len!=others.len { return false,blot_error::Error.none; }
  for x,index in goals {
   let y=others[index]; if x.kind!=y.kind||x.name!=y.name||x.operator!=y.operator||x.identity!=y.identity { return false,blot_error::Error.none; }
   let first: u32[4]=[x.ty,x.other,x.result,x.signature]; let second: u32[4]=[y.ty,y.other,y.result,y.signature];
   for value,i in first { if (value==0)!=(second[i]==0) { return false,blot_error::Error.none; } if value!=0 { let same,e=equal(self_,value,second[i],local+1,depth+1); if e!=blot_error::Error.none||!same { return same,e; } } }
  }
  return equal(self_,a.a,b.a,local+1,depth+1);
 }
 if a.tag==blot_eval_type_evidence::Tag.function||a.tag==blot_eval_type_evidence::Tag.state_provider {
  let x,e=equal(self_,a.a,b.a,local,depth+1); if e!=blot_error::Error.none||!x { return x,e; } let y,error=equal(self_,a.b,b.b,local,depth+1); if error!=blot_error::Error.none||!y { return y,error; }
  if a.tag==blot_eval_type_evidence::Tag.function { return row(self_,a.c,b.c,local,depth+1); } return equal(self_,a.c,b.c,local,depth+1);
 }
 if a.tag==blot_eval_type_evidence::Tag.usage { if a.b!=b.b||(a.c==0)!=(b.c==0) { return false,blot_error::Error.none; } let same,e=equal(self_,a.a,b.a,local,depth+1); if e!=blot_error::Error.none||!same { return same,e; } if a.c==0 { return true,blot_error::Error.none; } return equal(self_,a.c,b.c,local,depth+1); }
 if a.tag==blot_eval_type_evidence::Tag.provider { let same,e=equal(self_,a.a,b.a,local,depth+1); if e!=blot_error::Error.none||!same { return same,e; } return row(self_,a.c,b.c,local,depth+1); }
 if a.tag==blot_eval_type_evidence::Tag.array||a.tag==blot_eval_type_evidence::Tag.list||a.tag==blot_eval_type_evidence::Tag.cursor||a.tag==blot_eval_type_evidence::Tag.resolver { return equal(self_,a.a,b.a,local,depth+1); }
 if a.tag==blot_eval_type_evidence::Tag.projection||a.tag==blot_eval_type_evidence::Tag.nominal||a.tag==blot_eval_type_evidence::Tag.product||a.tag==blot_eval_type_evidence::Tag.record {
  if (a.tag==blot_eval_type_evidence::Tag.projection||a.tag==blot_eval_type_evidence::Tag.nominal)&&(a.a!=b.a||a.b!=b.b) { return false,blot_error::Error.none; }
  if a.tag==blot_eval_type_evidence::Tag.projection { let x=self_.view.projection(left); let y=self_.view.projection(right); var scope=x.scope; if scope>=local { if scope>0xffffffff-self_.shift { return false,blot_error::Error.evidence_limit; } scope+=self_.shift; } if x.member!=y.member||scope!=y.scope||x.goal!=y.goal { return false,blot_error::Error.none; } }
  let xs=self_.view.children(left); let ys=self_.view.children(right); if xs.len!=ys.len { return false,blot_error::Error.none; }
  for x,index in xs { if a.tag==blot_eval_type_evidence::Tag.record&&index%2==0 { if x!=ys[index] { return false,blot_error::Error.none; } } else { let same,e=equal(self_,x,ys[index],local,depth+1); if e!=blot_error::Error.none||!same { return same,e; } } } return true,blot_error::Error.none;
 }
 if a.tag==blot_eval_type_evidence::Tag.type_constructor { return a.a==b.a&&a.b==b.b,blot_error::Error.none; }
 if a.tag==blot_eval_type_evidence::Tag.absent||a.tag==blot_eval_type_evidence::Tag.scoped||a.tag==blot_eval_type_evidence::Tag.erased_proof { return false,blot_error::Error.unresolved_type; } return true,blot_error::Error.none;
}
fn row(self_: Comparison&,left: u32,right: u32,local: i64,depth: i64) -> bool,Error {
 let err=step(self_,depth); if err!=blot_error::Error.none { return false,err; }
 if left>=self_.view.effects.rows.len||right>=self_.view.effects.rows.len { return false,blot_error::Error.type_mismatch; }
 let a=self_.view.effects.rows[left]; let b=self_.view.effects.rows[right]; if (a.formal==0)!=(b.formal==0) { return false,blot_error::Error.none; }
 if a.formal!=0 { let same,e=equal(self_,a.formal,b.formal,local,depth+1); if e!=blot_error::Error.none||!same { return same,e; } }
 let xs=self_.view.effects.rowLabels(left); let ys=self_.view.effects.rowLabels(right); if xs.len!=ys.len||xs.len>256 { return false,blot_error::Error.none; } var used: bool[256]=[false;256];
 for x in xs {
  var found=false;
  for y,index in ys {
   let e=step(self_,depth); if e!=blot_error::Error.none { return false,e; } if used[index] { continue; } let first=self_.view.effects.operation(x); let second=self_.view.effects.operation(y);
   if first.identity!=second.identity||first.instance!=second.instance { continue; } let args=self_.view.effects.operationArguments(x); let other=self_.view.effects.operationArguments(y); if args.len!=other.len { continue; }
   var same=true; for expected,i in args { let matched,error=equal(self_,expected,other[i],local,depth+1); if error!=blot_error::Error.none { return false,error; } if !matched { same=false; break; } }
   if !same { continue; } used[index]=true; found=true; break;
  }
  if !found { return false,blot_error::Error.none; }
 }
 return true,blot_error::Error.none;
}
fn validate(view: View,id: u32,goal: blot_eval_type_evidence::Goal,remaining: i64&) -> Error {
 let n=view.node(id); if goal.kind!=blot_check_types::ObligationKind.contract||goal.identity.unit!=n.a||goal.identity.decl!=n.b||goal.ty==0||goal.ty>=view.nodes.len { return blot_error::Error.type_mismatch; }
 let tuple=view.node(goal.ty); if tuple.tag!=blot_eval_type_evidence::Tag.product||tuple.a>view.extra.len||tuple.b>view.extra.len-tuple.a { return blot_error::Error.type_mismatch; }
 let expected=view.children(goal.ty); let actual=view.children(id); if expected.len!=actual.len { return blot_error::Error.type_mismatch; }
 var proof=Comparison {view,view.projection(id).scope,remaining}; for left,index in expected { let same,e=equal(proof,left,actual[index],0,0); if e!=blot_error::Error.none { return e; } if !same { return blot_error::Error.type_mismatch; } } return blot_error::Error.none;
}
